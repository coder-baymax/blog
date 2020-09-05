---
layout:     post
title:      "Leectode Magic - DeepCopy"
subtitle:   "算法笔记：深度拷贝类型时的小魔法"
date:       2020-06-18 12:00:00
author:     "Baymax"
header-img: "img/post-bg-agt-6.jpg"
catalog: true
tags:
    - Algorithm
    - Leetcode
---

## DeepCopy的小魔法

浅拷贝和深拷贝的区别就不赘述了，这里给个传送门：

>  [Object_copying - wiki](https://en.wikipedia.org/wiki/Object_copying)

其实在python中就已经有了deepcopy这个函数，有需求的话可以直接使用。但是在其他的语言里，很多就不包含这个了，如果需要深拷贝的话要自己实现。

在深拷贝一个对象的时候，对象可能会有很复杂的引用关系，一般可以画成一张有向图，但是需要注意的是，这个图是可能是有环的。因此其实深拷贝的算法也是图的DFS和BFS的变种算法，在进行有限次数的图遍历以后，就可以完成对象的复制了。

### 比较好想到的方案

- 第一遍循环遍历每一个对象，并且使用一个Map来保存每一个对象的复制
- 第二遍循环再次遍历每一个对象，根据引用关系后对Map里面保存的复制进行处理
- 返回需要复制的根对象的副本

### 针对无环对象

如果对象确保无环的话，那么直接使用递归每次返回对象的copy即可，由于无环递归可以正常返回。

### 加一点魔法

如果使用Map保存所有的复制，会有比较大的额外空间，同时代码也会比较长。我们可以选择直接将副本挂在在原对象上，减少额外空间占用，并且简化代码。

## Leetcode题目

### [克隆图](https://leetcode-cn.com/problems/clone-graph/)

> 给你无向 连通 图中一个节点的引用，请你返回该图的 深拷贝（克隆）。
> 图中的每个节点都包含它的值 val（int） 和其邻居的列表（list[Node]）。

```python
class Solution:
    def cloneGraph(self, node: 'Node') -> 'Node':
        if node is None:
            return node
        elif hasattr(node, 'clone'):
            return getattr(node, 'clone')
        else:
            clone = Node(node.val, node.neighbors)
            setattr(node, 'clone', clone)
            try:
                return clone
            finally:
                clone.neighbors = [self.cloneGraph(x) for x in clone.neighbors]
```

这个就是很典型的一个图复制，并且是一个无向图，无向图的每一条边都是一个环。

### [复杂链表的复制](https://leetcode-cn.com/problems/fu-za-lian-biao-de-fu-zhi-lcof/)

> 请实现 copyRandomList 函数，复制一个复杂链表。在复杂链表中，每个节点除了有一个 next 指针指向下一个节点，还有一个 random 指针指向链表中的任意节点或者 null。

```python
class Solution:
    def copyRandomList(self, head: 'Node') -> 'Node':
        if head is None:
            return head
        elif hasattr(head, 'clone'):
            return getattr(head, 'clone')
        else:
            clone = Node(head.val, head.next, head.random)
            setattr(head, 'clone', clone)
            try:
                return clone
            finally:
                clone.next = self.copyRandomList(clone.next)
                clone.random = self.copyRandomList(clone.random)
```

这个问题与上面的图复制类似，如果直接使用递归返回，会导致random指向的对象被复制多次，导致bug产生。

如果使用Java或者其他不能动态增加对象成员的语言，这里的操作会变得复杂，但本质的想法是不变的：

- 首先根据next来遍历，让每个对象的next指向自己的副本
- 第二次遍历的时候，调整每个副本的next和random指向
- 返回根节点的副本