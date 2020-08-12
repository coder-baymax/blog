---
layout:     post
title:      "树型文件系统设计"
subtitle:   "基于django和mysql"
date:       2020-07-22 12:00:00
author:     "Baymax"
header-img: "img/post-bg-teq-1.jpg"
catalog: true
tags:
    - Code Design
    - Project
---

> PM：我们需要做一个简单的文件系统  
> 臭开发：好呀，怎么样简单的文件系统呢  
> PM：很简单，像windows里面那样的就行了  
> 臭开发：...  

## 需求解构

产品的需求是做一个类似windows系统中的文件系统，根据这个一句话需求，我们可以引申出几个基本的需求要点：

1. 文件系统是一个树型结构，其中文件夹内可以包含子文件（不排除非文件夹也包含树型结构的可能）
2. 需要支持多种文件类型，不同的文件类型可以支持不同的操作；但是都需要支持类似创建、删除之类的共性操作
3. 未来极其有可能需要挂上权限系统，不过这暂时只是个预期，只要设计的时候考虑好不要加不上就行

### 整体设计

在需求解构之后，PM沟通将第三点权限和文件系统分开，针对文件系统，主要由两部分工作量组成：

1. 文件系统本身的树型结构的CRUD
2. 在请求文件系统时需要走统一的入口，但是不同的文件类型又需要支持不同的操作

因此，我们从各种不同的文件类型中将树型结构和通用方法抽象出来，并且在请求上也将请求分为通用外部请求和针对某种特定文件类型的个性化请求，如下图：
![](/img/in-post/2020-08-22-design-tree-file-system/file-system.jpg)

## 树型结构实现

在一般的sql数据库中，没有直接对树型结构类型的支持，因此需要一些额外的支持来提供，在[《SQL反模式》](https://book.douban.com/subject/6800774/)这本书中的第三章，有树形结构存储的方案介绍，最后我选择了其中的两种：

- 一是最常见的直接给每个节点添加parent_id的外键引用，称为邻接表
- 二是相对更复杂一些，给每一个祖先-孩子关系保存一张映射表，称为闭包表

另外书中给出的另一种嵌套集方案难以维护而且收益很小，基本不再使用了。而递归查询和枚举路径可以直接作为邻接表的优化路径，因此可以在邻接表不能满足性能需求的时候，作为改进方案使用。

### 邻接表

邻接表的存储形式非常的简单直接，即对于每个孩子保存一条指向其父亲的关联，正向可以直接找到它的父亲，逆向可以通过父亲找到所有的孩子，在反模式一书中的示例如下图：

![](/img/in-post/2020-08-22-design-tree-file-system/design-1.jpg)

如果放到Django项目里面会类似于下面这种：

```python
class Node(models.Model):
    name = models.TextField(null=True, blank=True)
    update_time = models.DateTimeField(null=False, blank=False, default=datetime.utcnow)
    create_time = models.DateTimeField(null=False, blank=False, default=datetime.utcnow)
    parent = models.ForeignKey("self", on_delete=models.CASCADE, null=True, related_name="sons")
```

其中需要注意的是针对自己的引用需要用字符串"self"或者类名来代替，否则是没法正确引用的。

#### 效率陷阱

在这样的设计方式下，增删改都会比较容易，毕竟每个节点只和它的父亲有关联。唯一可能会遇上陷阱的是查询操作，如果只查询直接孩子是比较容易的，相对复杂的是查询所有的子孙，如果不注意的话可能会写成下面这样：

```python
    def get_sons(self, root):
        return {'name': root.name, 'update_time': root.update_time.timestamp(),
                'sons': [self.get_sons(x) for x in Node.objects.filter(parent=root)]}
```

这样的代码乍一看是没什么问题，也是通过递归的方式拉取所有的文件，但是等文件数量变大之后就会发现时间大大增加，在我们的系统中，当单个用户的文件数量达到四五百的数量级时，上面这段代码的运行耗时就已经来到了500ms。

这里的主要原因是由于使用了DFS编写了这一段搜索代码，导致请求数据库的次数等于节点的数目，当数据增长之后，请求的次数激增，可以通过单元测试来复现这个现象：

```python
class TreeTest(TestCase):
    def setUp(self) -> None:
        super(TreeTest, self).setUp()
        self.root_node = Node.objects.create(name='root')
        for i in range(3):
            parent = self.root_node
            for j in range(3):
                parent = Node.objects.create(name='sons_{}_{}'.format(i, j), parent=parent)

    @override_settings(DEBUG=True)
    def test_scan(self):
        self.get_sons(self.root_node)
        for item in connection.queries:
            print(item)
```

上面的代码首先创建了一个根节点，然后下面有3层结构，每层均有3个节点的树，然后使用get_sons函数遍历整棵树，运行之后我们可以看到下面的sql查询列表：

```bash
{'sql': 'SELECT "adjacency_list_node"."id", "adjacency_list_node"."name", "adjacency_list_node"."update_time", "adjacency_list_node"."create_time", "adjacency_list_node"."parent_id" FROM "adjacency_list_node" WHERE "adjacency_list_node"."parent_id" = 1', 'time': '0.000'}
{'sql': 'SELECT "adjacency_list_node"."id", "adjacency_list_node"."name", "adjacency_list_node"."update_time", "adjacency_list_node"."create_time", "adjacency_list_node"."parent_id" FROM "adjacency_list_node" WHERE "adjacency_list_node"."parent_id" = 2', 'time': '0.000'}
{'sql': 'SELECT "adjacency_list_node"."id", "adjacency_list_node"."name", "adjacency_list_node"."update_time", "adjacency_list_node"."create_time", "adjacency_list_node"."parent_id" FROM "adjacency_list_node" WHERE "adjacency_list_node"."parent_id" = 3', 'time': '0.000'}
{'sql': 'SELECT "adjacency_list_node"."id", "adjacency_list_node"."name", "adjacency_list_node"."update_time", "adjacency_list_node"."create_time", "adjacency_list_node"."parent_id" FROM "adjacency_list_node" WHERE "adjacency_list_node"."parent_id" = 4', 'time': '0.000'}
{'sql': 'SELECT "adjacency_list_node"."id", "adjacency_list_node"."name", "adjacency_list_node"."update_time", "adjacency_list_node"."create_time", "adjacency_list_node"."parent_id" FROM "adjacency_list_node" WHERE "adjacency_list_node"."parent_id" = 5', 'time': '0.000'}
{'sql': 'SELECT "adjacency_list_node"."id", "adjacency_list_node"."name", "adjacency_list_node"."update_time", "adjacency_list_node"."create_time", "adjacency_list_node"."parent_id" FROM "adjacency_list_node" WHERE "adjacency_list_node"."parent_id" = 6', 'time': '0.000'}
{'sql': 'SELECT "adjacency_list_node"."id", "adjacency_list_node"."name", "adjacency_list_node"."update_time", "adjacency_list_node"."create_time", "adjacency_list_node"."parent_id" FROM "adjacency_list_node" WHERE "adjacency_list_node"."parent_id" = 7', 'time': '0.000'}
{'sql': 'SELECT "adjacency_list_node"."id", "adjacency_list_node"."name", "adjacency_list_node"."update_time", "adjacency_list_node"."create_time", "adjacency_list_node"."parent_id" FROM "adjacency_list_node" WHERE "adjacency_list_node"."parent_id" = 8', 'time': '0.000'}
{'sql': 'SELECT "adjacency_list_node"."id", "adjacency_list_node"."name", "adjacency_list_node"."update_time", "adjacency_list_node"."create_time", "adjacency_list_node"."parent_id" FROM "adjacency_list_node" WHERE "adjacency_list_node"."parent_id" = 9', 'time': '0.000'}
{'sql': 'SELECT "adjacency_list_node"."id", "adjacency_list_node"."name", "adjacency_list_node"."update_time", "adjacency_list_node"."create_time", "adjacency_list_node"."parent_id" FROM "adjacency_list_node" WHERE "adjacency_list_node"."parent_id" = 10', 'time': '0.000'}
```

简单数一下我们发现一共有10次select请求（包含了根节点），这是完全等于节点数量的，因此如果一棵文件树有四五百个节点的话，会拉四五百四sql数据库，这个效率就非常恐怖了。

#### 改进方案

这里的改进也比较容易想到，我们只需要把DFS的代码改成BFS代码就可以了，会将查询sql的次数从正比于文件节点数量改造成正比于树的深度，由于文件都是用户创建的，能有个10-20层的目录深度已经接近极限了，这样的性能完全符合要求，改造后的代码：

```python
    def get_sons(self, root):
        index, node_list = 0, [root]
        while index < len(node_list):
            temp_len = len(node_list)
            for node in Node.objects.filter(parent_id__in=[x.id for x in node_list[index:]]):
                node_list.append(node)
            index = temp_len
        node_dict = {x.id: {'name': x.name, 'parent_id': x.parent_id, 'sons': []}
                     for x in node_list}
        for node in node_dict.values():
            if node['parent_id']:
                node_dict[node['parent_id']]['sons'].append(node)
        return node_dict[root.id]
```

使用同样的测试用例可以得到如下的结果：

```bash
{'sql': 'SELECT "adjacency_list_node"."id", "adjacency_list_node"."name", "adjacency_list_node"."update_time", "adjacency_list_node"."create_time", "adjacency_list_node"."parent_id" FROM "adjacency_list_node" WHERE "adjacency_list_node"."parent_id" IN (1)', 'time': '0.000'}
{'sql': 'SELECT "adjacency_list_node"."id", "adjacency_list_node"."name", "adjacency_list_node"."update_time", "adjacency_list_node"."create_time", "adjacency_list_node"."parent_id" FROM "adjacency_list_node" WHERE "adjacency_list_node"."parent_id" IN (2, 5, 8)', 'time': '0.000'}
{'sql': 'SELECT "adjacency_list_node"."id", "adjacency_list_node"."name", "adjacency_list_node"."update_time", "adjacency_list_node"."create_time", "adjacency_list_node"."parent_id" FROM "adjacency_list_node" WHERE "adjacency_list_node"."parent_id" IN (3, 6, 9)', 'time': '0.000'}
{'sql': 'SELECT "adjacency_list_node"."id", "adjacency_list_node"."name", "adjacency_list_node"."update_time", "adjacency_list_node"."create_time", "adjacency_list_node"."parent_id" FROM "adjacency_list_node" WHERE "adjacency_list_node"."parent_id" IN (4, 7, 10)', 'time': '0.000'}
```

从上面的结果我们可以看到，这一次的结果只请求了4次数据库，和树的深度一致，大大减少了请求的时间浪费。

### 闭包表

闭包表在数据结构上需要新增一张关联表，分别记录每一对祖先和子孙，最好可以顺带记录两节点的距离（自己和自己默认为0）方便查询，在sql反模式书中的解释图如下：

![](/img/in-post/2020-08-22-design-tree-file-system/design-2.jpg)

可以看到其实就是在每两个有祖先-子孙关系的节点中，加入了关联关系，没有共同祖先的节点，就没有关联关系。在邻接表中，我们如果查询以某个节点为根的树或者所有祖先，都需要使用递归来查找，但是在闭包表中，就变得非常简单，只需要找到与该节点有关联的节点即可，都可以用一次数据库请求得到，相应的，插入、删除和移动的复杂度就变高了。

在Django项目里面，我们创建节点的model，并加入闭包表：

```python
class Node(models.Model):
    name = models.TextField(null=True, blank=True)
    update_time = models.DateTimeField(null=False, blank=False, default=datetime.utcnow)
    create_time = models.DateTimeField(null=False, blank=False, default=datetime.utcnow)

    objects = NodeManager()


class NodeRelation(models.Model):
    ancestor = models.ForeignKey(Node, on_delete=models.CASCADE, related_name='ancestor')
    posterity = models.ForeignKey(Node, on_delete=models.CASCADE, related_name='posterity')
    level = models.IntegerField(null=False, blank=False, db_index=True, default=0)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=['ancestor', 'posterity'], name='unique_relation')
        ]
```

在闭包表中进行CRUD的时候，就不能像原来的邻接表那么简单，需要增加一些额外的步骤：

- 增加一个节点时，需要批量添加它和它祖先的关联关系
- 删除一个节点时，需要删除它和它所有的子孙节点，关联关系可以通过外键限制自动删除
- 移动一个节点时，需要小心地处理它的关联关系，可以将它和它所有的子孙视为一个集合，删除所有集合和外部的关联，并重建它们和新祖先的所有关联

需要额外注意的是在删除的时候不能仅删除关联关系，必须删除节点，否则节点就会成为游离节点除非写脚本扫描~~或者删库跑路~~，就永远没办法触达这些节点了。

#### Code Time

我们在写闭包集代码的时候，可以使用Django建议的设计风格，将这部分复杂的操作封装到model层中去，这样对外就可以忽略掉NodeRelation的影响，最好外部的代码都不要直接针对NodeRelation进行操作，这样可以保障数据的完整性。

话不多说，直接上代码吧，其中的创建、删除相对比较简单，如下：

```python
class NodeManager(models.Manager):

    def create_with_relation(self, parent_id=None, **kwargs):
        node = self.create(**kwargs)
        relations = [] if parent_id is None else [NodeRelation(
            ancestor_id=x.ancestor_id, posterity=node, level=x.level + 1
        ) for x in NodeRelation.objects.filter(posterity=parent_id)]
        relations.append(NodeRelation(ancestor=node, posterity=node, level=0))
        NodeRelation.objects.bulk_create(relations)
        return node

    def delete_with_relation(self, node_id):
        node_ids = [x['posterity_id'] for x in NodeRelation.objects.filter(
            ancestor_id=node_id).values('posterity_id')]
        self.filter(id__in=node_ids).delete()
```

获取目录树的方案还是需要有两段请求来实现，先获取树中所有距离为1的关联，再根据关联进行组合：

```python
    def get_tree(self, node_id):
        node_dict = defaultdict(lambda: {'name': '', 'sons': []})
        for relation in NodeRelation.objects.filter(level=1, posterity_id__in=Subquery(
                NodeRelation.objects.filter(ancestor_id=node_id).values('posterity_id'))):
            node_dict[relation.ancestor_id]['sons'].append(node_dict[relation.posterity_id])
        for node in self.filter(id__in=list(node_dict.keys())):
            node_dict[node.id]['name'] = node.name
        return node_dict[node_id]
```

最复杂的部分是移动操作，移动的时候需要先删除原有的关联，再加入所有的新关联（这里创建新关联的时候使用了将数据载入到内存里进行操作，当然也可以直接使用sql语句进行，只是可读性上会更差一些）：

```python
    def move_with_relation(self, node_id, parent_id):
        ancestor_query = ~models.Q(ancestor_id=node_id) & models.Q(ancestor_id__in=Subquery(
            NodeRelation.objects.filter(posterity_id=node_id).values('ancestor_id')))
        posterity_query = models.Q(posterity_id__in=Subquery(
            NodeRelation.objects.filter(ancestor_id=node_id).values('posterity_id')))
        NodeRelation.objects.filter(ancestor_query & posterity_query).delete()

        ancestor_list = list(NodeRelation.objects.filter(posterity_id=parent_id))
        posterity_list = list(NodeRelation.objects.filter(ancestor_id=node_id))
        new_relations = [NodeRelation(
            ancestor_id=x.ancestor_id, posterity_id=y.posterity_id, level=x.level + y.level + 1
        ) for x in ancestor_list for y in posterity_list]
        NodeRelation.objects.bulk_create(new_relations)
```

#### 效率陷阱

闭包表看似是针对树型结构存储的更好的解决方案，它在获取任意节点为根的整棵树、以及所有祖先都有着更好的性能。

但是，闭包表也有两个比较明显的问题：

- 在空间复杂度上，这里的实际上是 $n^2$ 复杂度的，但是这仅针对只有一根分支的极限情况，在通常情况下规模会小很多，但是使用的空间显然也比邻接表大多了
- 另外一个比较致命的问题是在移动节点的时候，这里会涉及一个笛卡尔积的操作，如果移动一个深度为 $d$ 且节点数量为 $n$ 的子树的话，会导致一个 $d \times n$ 复杂度的操作

如果说我们移动一个有几万个子文件的目录，将它移动到一个5层深度的目录下，就会涉及几十万条关联数据的删除和新增，如果这种操作频繁进行，那么数据库肯定不堪重负。

### 邻接表++

如果项目里面已经使用了邻接表，或者说不能接受闭包表的代价，那么有什么更好的办法呢？答案是肯定的，反模式中介绍的另外两种，其实就可以作为邻接表的改进和优化方案。

#### 递归查询

这里的递归查询不是指代码内部的递归查询，而是特指数据库中支持的递归查询操作。针对Oracle，是有相关的操作支持的，当然并不是所有的公司都用得起，另外连马爸爸家都放弃了，可见Oracle也不是万能药。在Mysql这边，从Mysql8开始支持with子句用于递归查询。

有了递归查询之后，原本的查询就变得简单起来了，只要将代码中的递归改写成sql语句就可以了，可以参考：[Stackoverflow: mysql-recursive-query](https://stackoverflow.com/questions/20215744/how-to-create-a-mysql-hierarchical-recursive-query)

但是如果mysql版本是5.6或者5.7该怎么办呢？其实也可以有解决方案的，一个是提着刀（误）去找产品给文件系统加一个深度限制，这样的话可以直接通过复制黏贴一把梭+有限的join操作实现，当然这样实在是太不优雅了，并且join那么多，效率也不行；另外一个是在上面Stackoverflow中也提到了，直接使用sql的CTE公式去做，但是这种骚操作的效果也并不好，节点数量一多效率就急剧下降，这个在答案中也有相应的解释。

所以总的来说，想要使用递归查询的话，数据库的支持是一个必要条件，否则可能还不如代码实现的BFS效率高。

#### 枚举路径

这种优化的方式其实非常简单也好理解，就是在每个节点增加一个字段，记录当前节点对应的路径信息，类似于文件路径。这样在搜索以某个节点为根的树的时候，直接使用Like子句搜索前缀就可以，比如当前节点的路径是：1/2/3，那么找到文件路径以1/2/3开头的即可拉出所有节点。

这种操作的方式其实和闭包集方案有一些类似，即在移动的时候需要修改所有相关节点的路径信息，这里涉及与节点数量一致复杂度的更新操作，但是在插入和删除的时候，都不需要补充关联信息。

如果作为邻接表的升级，枚举路径其实是用移动操作的时间换取了拉取树型节点的时间，建议作为递归查询方案无法实施之后的备选。

## 总结

在设计类似于文件、类别、角色等系统的时候，都可能会遇到树型结构的设计问题，之前也遇到了有一个应届生跑来问我类别有最多有多少层，然后随口的回答让我收获了一段九层嵌套if语句的代码。

至于使用怎样的设计，还是需要考量实际的需求和使用场景，我们可以分几种情况：

- 如果说没有拉取树型结构的需求，每次都只需要拉取当前父亲的第一层孩子（许多文件系统的前端是这样的），那么其实邻接表就是最优的，任何操作速度都足够快
- 如果涉及了频繁的拉取整棵树的操作，但是又很少出现移动，或者说移动基本都由系统或者后台进行（比如带层级的分类体系），那么闭包表很可能是最好的选择
- 有的时候可能是原有的邻接表不符合性能要求，需要改造，那么可以根据数据库的情况，选择使用递归查询或者枚举路径，或者干脆直接改造成闭包表结构
