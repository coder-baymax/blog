---
layout:     post
title:      "树型文件系统设计"
subtitle:   "基于django和mysql"
date:       2020-07-22 12:00:00
author:     "Baymax"
header-img: "img/post-bg-teq-1.jpg"
catalog: true
tags:
    - Architect
    - Project
---

> PM：我们需要做一个简单的文件系统  
> 臭开发：好呀，怎么样简单的文件系统呢  
> PM：很简单，像windows里面那样的就行了  
> 臭开发：...  

## 需求描述

产品的需求是做一个类似windows系统中的文件系统，同时支持文件的移动、删除、复制等常见操作，分析这个需求之后，可以引申出几个基本的需求要点：

1. 文件系统是一个树型结构，其中文件夹内可以包含子文件，另外不排除非文件夹也包含树型结构的可能
2. 需要支持多种文件类型，不同的文件类型可以支持不同的操作；但是都需要支持类似创建、删除之类的共性操作
3. 针对不同的文件类型，还可能存在不同的筛选项；在文件列表中，根据不同的文件类型还会有不同的展示字段
4. 未来极有可能需要加上权限系统，与文件系统进行协作，不过这暂时只是个预期，只要设计的时候考虑好不要加不上就行

### 整体设计

在需求分析之后，和产品沟通将权限和文件系统分开开发，权限作为另一个迭代的大模块进行单独设计和开发。针对文件系统的需求，主要由几部分工作组成：

1. 文件系统本身的树型结构的数据库设计和增删改查
2. 文件系统的框架设计，在操作不同文件类型的时候支持每种类型定义不同的行为
3. 获取文件列表的接口需要在文件系统中写好，并且对不同文件类型支持不同的展示项和筛选项

因此，我们从各种不同的文件类型中将树型结构和通用方法抽象出来，并且在请求上也将请求分为通用外部请求和针对某种特定文件类型的个性化请求，如下图：

![](/img/in-post/2020-08-22-design-tree-file-system/file-system.jpg)

## 数据库方案

在大多数sql数据库中，没有直接对树型数据结构类型的支持，因此需要一些额外的设计，在[《SQL反模式》](https://book.douban.com/subject/6800774/)这本书中的第三章，介绍了常用的几种树形结构的数据库设计方案，其中两种最具代表性：

- 一是给每个树节点添加parent_id的外键，指向其父亲，即邻接表方案
- 二是为每一个祖先-孩子关系保存一张映射表，即闭包表方案

另外书中给出的另一种嵌套集方案难以维护而且效率不高，已经很少有人使用了。对于邻接表方案，还有递归查询和枚举路径两种优化可以选择，因此在邻接表不能满足性能需求的时候，还可以进行持续改进。

### 邻接表方案

邻接表的存储形式非常的简单直接，即对于每个孩子保存一条指向其父亲的关联，正向可以直接找到它的父亲，逆向可以通过父亲找到所有的孩子，在反模式一书中的示例如下图：

![](/img/in-post/2020-08-22-design-tree-file-system/design-1.jpg)

放到Django项目里面，对于model的定义如下：

```python
class Node(models.Model):
    name = models.TextField(null=True, blank=True)
    update_time = models.DateTimeField(null=False, blank=False, default=datetime.utcnow)
    create_time = models.DateTimeField(null=False, blank=False, default=datetime.utcnow)
    parent = models.ForeignKey("self", on_delete=models.CASCADE, null=True, related_name="sons")
```

其中需要注意的是，针对自身的引用需要用字符串"self"或者类名来代替，这样才能在Django的框架里正确地创建外键关联。

#### 效率陷阱

在这样的设计方式下，增删改都会比较容易，毕竟每个节点只和它的父亲有关联，每次改动只需要修改parent这个字段即可。唯一可能会遇上问题的是查询操作，如果只查询直接孩子也是相对容易的，比较复杂的是查询某个节点对应的所有的子孙，这段代码需要用递归实现，可能会写成下面这样：

```python
def get_sons(self, root):
    return {'name': root.name, 'update_time': root.update_time.timestamp(),
            'sons': [self.get_sons(x) for x in Node.objects.filter(parent=root)]}
```

这段代码乍一看是没什么问题，也是通过递归的方式拉取所有的文件，但是等文件数量上升之后就会发现耗时大大增加，在我们的系统中，当单个用户的文件数量达到四五百的数量级时，上面这段代码的运行耗时就已经达到500ms。

耗时激增主要原因是：这里使用了深度优先搜索编写查询代码，导致请求数据库的次数正比于树形数据结构的节点数目，当数据增长之后，请求数据库的次数激增，可以通过单元测试来复现这个现象：

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

上面的测试用例首先创建了一个根节点，然后下面有3层结构，每层均有3个节点，然后使用get_sons函数获取整棵树的，最后通过框架自带的组件打印出所有的数据库查询语句，运行之后我们可以看到下面的结果：

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

简单数一下会发现这里一共有10次select查询（包含根节点），这正好等于节点数量，假设需要查询的文件树有四五百个节点的话，就会请求四五百次sql数据库，这个耗时就非常恐怖了。

#### 改进方案

上述问题的改进方案就是减少对数据库的查询次数，也就是把深度优先搜索改成宽度优先搜索，这会将查询sql的次数从正比于文件节点数量改造成正比于树的深度，由于文件都是用户创建的，能有个10-20层的目录深度已经接近极限了，这样就可以符合性能要求了，改造后的代码如下：

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

使用同样的测试用例可以得到如下结果：

```bash
{'sql': 'SELECT "adjacency_list_node"."id", "adjacency_list_node"."name", "adjacency_list_node"."update_time", "adjacency_list_node"."create_time", "adjacency_list_node"."parent_id" FROM "adjacency_list_node" WHERE "adjacency_list_node"."parent_id" IN (1)', 'time': '0.000'}
{'sql': 'SELECT "adjacency_list_node"."id", "adjacency_list_node"."name", "adjacency_list_node"."update_time", "adjacency_list_node"."create_time", "adjacency_list_node"."parent_id" FROM "adjacency_list_node" WHERE "adjacency_list_node"."parent_id" IN (2, 5, 8)', 'time': '0.000'}
{'sql': 'SELECT "adjacency_list_node"."id", "adjacency_list_node"."name", "adjacency_list_node"."update_time", "adjacency_list_node"."create_time", "adjacency_list_node"."parent_id" FROM "adjacency_list_node" WHERE "adjacency_list_node"."parent_id" IN (3, 6, 9)', 'time': '0.000'}
{'sql': 'SELECT "adjacency_list_node"."id", "adjacency_list_node"."name", "adjacency_list_node"."update_time", "adjacency_list_node"."create_time", "adjacency_list_node"."parent_id" FROM "adjacency_list_node" WHERE "adjacency_list_node"."parent_id" IN (4, 7, 10)', 'time': '0.000'}
```

从上面的结果可以看到，这一次测试用例只请求了4次数据库，和树的深度一致，大大减少了数据库请求的时间浪费。

### 闭包表

闭包表在数据结构上需要新增一张关联表，每一对拥有祖先-子孙关系的节点都需要在表中有一条记录，另外最好可以顺带记录两节点的距离（自己和自己默认为0）方便查询，在sql反模式书中的解释图如下：

![](/img/in-post/2020-08-22-design-tree-file-system/design-2.jpg)

从图中可以看到：闭包表其实就是在所有有祖先-子孙关系的节点中，加入了关联关系，没有共同祖先的节点，就没有关联关系。在邻接表中，我们如果查询以某个节点为根的整颗树，都需要使用递归来查找，但是在闭包表中，这个操作就变得非常简单——只需要找到与该节点有关联的节点即可，可以用一次数据库请求实现，相应的，插入、删除和移动的复杂度就变高了。

在Django项目里面，闭包表的数据model定义如下所示：

```python
class Node(models.Model):
    name = models.TextField(null=True, blank=True)
    update_time = models.DateTimeField(null=False, blank=False, default=datetime.utcnow)
    create_time = models.DateTimeField(null=False, blank=False, default=datetime.utcnow)

    objects = NodeManager()


class NodeRelation(models.Model):
    ancestor = models.ForeignKey(Node, on_delete=models.CASCADE, related_name='ancestor')
    descendant = models.ForeignKey(Node, on_delete=models.CASCADE, related_name='descendant')
    level = models.IntegerField(null=False, blank=False, db_index=True, default=0)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=['ancestor', 'descendant'], name='unique_relation')
        ]
```

在闭包表中进行增删改查的时候，就不能像原来的邻接表那么简单，需要增加一些额外的步骤：

- 增加一个节点时，需要批量添加它和它祖先的关联关系
- 删除一个节点时，需要删除它和它所有的子孙节点，在Django框架中，关联关系可以通过外键限制自动删除
- 移动一个节点时，需要小心地处理它的关联关系，将它和它所有的子孙视为一个集合，删除所有集合和外部的关联，并重建它们和新祖先的所有关联

需要注意的是在删除节点的时候不能仅删除关联关系，必须删除节点本身，否则节点就会成为游离节点，永远无法通过关联关系找到，就必须写额外的清理代码来处理它们了。

#### 代码设计

在写闭包表代码的时候，可以使用Django建议的设计风格，将这部分复杂的操作封装到model层中去，这样外部操作的时候就可以忽略掉NodeRelation的影响，另外外部的代码都不直接操作NodeRelation，这样可以保障数据只在一处代码修改，便于扩展和查错。

话不多说，直接上代码吧，其中的创建、删除相对比较简单，如下：

```python
class NodeManager(models.Manager):

    def create_with_relation(self, parent_id=None, **kwargs):
        node = self.create(**kwargs)
        relations = [] if parent_id is None else [NodeRelation(
            ancestor_id=x.ancestor_id, descendant=node, level=x.level + 1
        ) for x in NodeRelation.objects.filter(descendant=parent_id)]
        relations.append(NodeRelation(ancestor=node, descendant=node, level=0))
        NodeRelation.objects.bulk_create(relations)
        return node

    def delete_with_relation(self, node_id):
        node_ids = [x['descendant_id'] for x in NodeRelation.objects.filter(
            ancestor_id=node_id).values('descendant_id')]
        self.filter(id__in=node_ids).delete()
```

获取某个根节点的整棵树需要由两次请求实现，先获取所有的子孙节点，再获取它们之间所有距离为1的关联，根据关联信息构建树形结构信息：

```python
class NodeManager(models.Manager):

    def get_tree(self, node_id):
        node_dict = defaultdict(lambda: {'name': '', 'sons': []})
        for node in Node.objects.filter(descendant__ancestor_id=node_id):
            node_dict[node.id]['name'] = node.name
        for relation in NodeRelation.objects.filter(level=1, descendant_id__in=node_dict.keys()):
            node_dict[relation.ancestor_id]['sons'].append(node_dict[relation.descendant_id])
        return node_dict[node_id]
```

最复杂的部分是移动操作，移动的时候需要先删除原有的关联，再加入新关联。这里创建新关联的时候选择将数据载入到内存里进行操作，另一个选择是直接使用sql语句操作，只是这样的sql语句会非常复杂，复杂度很高，可读性很差，笔者不建议这么做：

```python
class NodeManager(models.Manager):

    def move_with_relation(self, node_id, parent_id):
        ancestor_query = ~models.Q(ancestor_id=node_id) & models.Q(ancestor_id__in=Subquery(
            NodeRelation.objects.filter(descendant_id=node_id).values('ancestor_id')))
        descendant_query = models.Q(descendant_id__in=Subquery(
            NodeRelation.objects.filter(ancestor_id=node_id).values('descendant_id')))
        NodeRelation.objects.filter(ancestor_query & descendant_query).delete()

        ancestor_list = list(NodeRelation.objects.filter(descendant_id=parent_id))
        descendant_list = list(NodeRelation.objects.filter(ancestor_id=node_id))
        new_relations = [NodeRelation(
            ancestor_id=x.ancestor_id, descendant_id=y.descendant_id, level=x.level + y.level + 1
        ) for x in ancestor_list for y in descendant_list]
        NodeRelation.objects.bulk_create(new_relations)
```

#### 效率陷阱

闭包表看似是针对树型结构存储更好的解决方案，它在获取任意节点为根的整棵树、获取节点的所有祖先都有着更好的性能。

但是，闭包表也有两个比较明显的问题：

- 在空间复杂度上，需要的空间其实是 $n^2$ 复杂度的，但是这仅针对极限情况，在日常使用下规模会小很多，但是使用的额外空间也比邻接表大多了
- 另外一个比较致命的问题是在移动节点的时候，这里会有一个笛卡尔积的操作，如果移动一个深度为 $d$ 且节点数量为 $n$ 的子树的话，会导致一个 $d \times n$ 复杂度的操作

如果移动一个有几万个子文件的目录，将它移动到一个5层深度的目录下，就会涉及几十万条关联数据的删除和新增，如果这种操作频繁进行，那么数据库肯定不堪重负。

### 邻接表优化

如果项目里面已经使用了邻接表，或者说不能接受闭包表的代价，那么有什么更好的办法呢？答案是肯定的，之前介绍过的两种方案就可以作为邻接表的改进和优化。

#### 递归查询

这里的递归查询不是指代码内部的递归查询，而是特指在某些数据库中支持的递归查询操作。对于Oracle数据库是有相关的操作支持的，不过连淘系都放弃Oracle了，可见Oracle也不是万能药。在Mysql这边，从Mysql8开始支持with子句用于递归查询。

有了递归查询之后，原本的查询就变得简单起来了，只要将代码中的递归改写成sql语句就可以了，可以参考：[Stackoverflow: mysql-recursive-query](https://stackoverflow.com/questions/20215744/how-to-create-a-mysql-hierarchical-recursive-query)。

但是如果mysql版本是5.6或者5.7该怎么办呢？其实也可以有解决方案的，一种是找产品经理给文件系统加一个深度限制，这样的话可以直接通过有限的join操作实现查询，不过这样实在是太不优雅了，并且join那么多，效率也不行；另外一种方案在上面Stackoverflow中也提到了，直接使用sql的CTE公式去做，但是这种骚操作的效果也不好，节点数量一多效率就急剧下降，主要原因是其中是否在集合内这个判断效率非常低下。

总的来说，想要使用递归查询的话，数据库的支持是一个必要条件，否则可能还不如代码实现的宽度优先搜索效率高。也因此在实际的项目中，考虑到数据库支持的问题，最早采用的就是宽度优先搜索来处理文件查找问题的。

#### 枚举路径

这种优化的方式其实很简单也很好理解，就是在每个节点增加一个字段，记录当前节点对应的路径信息，类似于文件路径。这样在搜索以某个节点为根的树的时候，可以利用sql字符串索引的特性，直接使用Like子句搜索前缀就可以，比如当前节点的路径是：1/2/3，那么找到文件路径以1/2/3开头的即可拉出所有节点。

这种操作的方式其实和闭包表方案有一些类似，即在移动的时候需要修改所有相关节点的路径信息，这里会有一个与节点数量成正比的复杂度的更新操作，但是在插入和删除的时候，都不需要更新路径信息。

作为邻接表的升级，枚举路径其实是用移动操作的时间换取了拉取树型节点的时间，建议作为递归查询方案无法实施之后的备选。另外闭包表其实也可以和邻接表共存，因此枚举路径也需要和闭包表进行对比，最后根据项目的实际情况进行选择。

## 系统框架设计

这里的框架设计主要目的是将文件系统相关的操作和每种文件类型自定义的操作分开，并且可以方便地增加文件类型而不用修改文件系统的相关代码，即增加文件系统的易用性和可扩展性。

### 使用回调切分模块

根据前面的需求分析，文件系统相关的操作都有可能影响具体文件的内容，整体流程大概会是下面这个顺序（以创建文件为例）：

![](/img/in-post/2020-08-22-design-tree-file-system/file-system-1.jpg)

在上图的流程中，请求首先进入文件系统，文件系统会创建文件，并且维护文件的关联关系，之后将创建好的文件model以及请求的所有参数传递给特定文件类型的模块做处理，具体模块根据这些信息处理完毕之后，将需要展示到文件列表中的数据再返回给文件系统，由文件系统更新到数据库内，最后返回给客户端，形成一个闭环。

### 自动注册回调函数

为了方便扩展文件类型，创建一个回调函数的虚基类，由每个类型模块自己定义，并且注册到文件系统中，这样文件系统就可以根据客户端操作的文件类型，调用对应的回调函数。

```python
class FileCallback(ABC, metaclass=CallbackMeta):
    file_type = None

    @classmethod
    @abstractmethod
    def create(cls, file: File, *args, **kwargs) -> Tuple[Dict, Any]:
        pass
```

为了让回调函数可以自动注册，定义的回调函数基类使用了python元类的特性，从而当有类型继承该基类时，系统可以自动将其注册到回调函数仓库中，下面是元类代码：

```python
class CallbackMeta(ABCMeta):
    def __new__(mcs, what, bases=None, attrs=None):
        new_class = super().__new__(mcs, what, bases, attrs)
        if what != "FileCallback":
            file_type = new_class.file_type
            for callback_type in ("create", "update", "delete", "dump", "load"):
                CallbackRepository.register(
                    file_type,
                    callback_type,
                    getattr(new_class, callback_type),
                    getattr(new_class, "batch_{}".format(callback_type)),
                )
        return new_class
```

最后在调用回调函数的时候，就可以直接使用回调仓库进行调用：

```python
@classmethod
def _call(cls, callback_type, file_type, *args, **kwargs):
    return getattr(CallbackRepository, callback_type)[file_type](*args, **kwargs)
```

## 写在最后

### 系统的变迁历史

**首个版本**

在首个版本，文件系统是用户级别隔离的，并且只有文件夹和工作流两种文件，因此在设计上是由两个model构成的，其中一个保存了文件目录信息，另一个保存了工作流信息。工作流记录了它属于哪个文件夹，文件夹也有同样的字段，记录了它的父目录。

当拉取用户目录时，需要递归拉取该用户所有的文件夹和工作流，并且这个操作是深度优先进行的，就出现了最早的性能陷阱，在发现之后改造成了宽度优先搜索。

**加入文件系统**

之后文件类型逐渐增加，并且删掉了用户级别的隔离，在这个版本，抽象出了文件系统的概念，构建了文件系统框架和回调模式，为后面文件类型的扩展打下了基础。

**新的效率挑战**

在加入文件系统之后，对它的依赖就开始逐步加深，当用户的文件数量增长到数万之后，原有的按层搜索文件树也变得效率低下，因此最终选择不改造原有表的基础上，补充一张关联表，实现闭包表方案。

### 结语

在设计类似于文件、分类、角色等系统的时候，都可能会遇到树型结构的设计问题，之前的工作中也有一个应届生跑来问我分类有最多有多少层级，然后随口的回答让我收获了一段九层嵌套if语句的代码。

至于使用怎样的设计，还是需要考量实际的需求和使用场景，我们可以分几种情况：

- 如果说没有拉取树型结构的需求，每次都只需要拉取当前父亲的第一层孩子（许多文件系统的前端是这样的），那么其实邻接表就是最优的，任何操作速度都足够快
- 如果涉及了频繁的拉取整棵树的操作，但是又很少出现移动，或者说移动基本都由系统或者后台进行（比如带层级的分类体系），那么闭包表很可能是最好的选择
- 有的时候可能是原有的邻接表不符合性能要求，需要改造，那么可以根据数据库的情况，选择使用递归查询或者枚举路径，或者干脆直接改造成闭包表结构

最后，不管选用什么样的方案，架构都是要跟随需求演进的，如果在早期就可以遇见之后的需求，那么在选择方案的时候就可以留下升级的余地，从而更优雅地进行代码重构。