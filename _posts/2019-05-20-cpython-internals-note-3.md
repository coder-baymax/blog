---
layout:     post
title:      "先有鸡还是先有蛋：object和type - Cpython Internals Notes (2)"
subtitle:   "Cpython虚拟机学习笔记系列"
date:       2019-5-20 12:00:00
author:     "Baymax"
header-img: "img/post-bg-agt-３.jpg"
catalog: true
tags:
    - Python
    - Study Notes
---

> Cpython虚拟机学习笔记系列  
> 油管视频：[CPython internals: A ten-hour codewalk](https://pg.ucsd.edu/cpython-internals.htm)  
> github博客：[zpoint/CPython-Internals](https://github.com/zpoint/CPython-Internals)  
> github源码：[python/cpython](https://github.com/python/cpython)  

## 继承与元类

在日常的编码中，经常会使用到继承，但是可能很少会用到元类。但实际上这个概念在所有面向对象的语言中都存在，比如在Java中就有Class类型，用于保存一个类的原信息，使用时可以通过反射拿到Class并且直接新建对象，这为Java增添了许多灵活性。

在Python中则更进一步，在Python语言中，一切皆为对象，那么定义的类肯定也是对象了。再加上Python是一种动态语言，它提供了非常方便的方式动态创建新类，比如像下面这样：

```python
new_class = type("new_class", (), {"message": lambda self: "hello world"})
x = new_class()
print x.message()

output:
hello world
```

我们就动态的创建了一个叫new_class的类，其中有一个叫message的方法，返回了"hello world"的信息。这个类和平时定义的类一样，都可以直接实例化，并且调用它的函数，但是似乎这有点多此一举，相比继承元类有哪些好处呢？

### 用元类实现策略模式

策略模式是一种常见的设计模式，如果使用继承的方式实现，那么通常会需要使用一个映射表来保存策略和其对应的处理类，或者好一些由每个类自己去注册，更进一步，使用元类可以让整个流程变得更加优雅：

```python
class StrategyFactory:
    strategy_map = {}

    @classmethod
    def register(cls, name, obj):
        cls.strategy_map[name] = obj

    @classmethod
    def get(cls, name, *args, **kwargs):
        return cls.strategy_map[name](*args, **kwargs)


class StrategyMeta(type):
    def __new__(mcs, what, bases=None, attrs=None):
        new_class = super().__new__(mcs, what, bases, attrs)
        StrategyFactory.register(what, new_class)
        return new_class


class Pet(metaclass=StrategyMeta):
    def __init__(self, name):
        self.name = name


class Cat(Pet):
    def call(self):
        print(f"{self.name}: miao miao")


class Dog(Pet):
    def call(self):
        print(f"{self.name}: wang wang")
```

这一段代码中我们创建了一个策略仓库、策略元类还有几个宠物类型，这个例子中我们简单地使用了类名作为策略名称。这样，我们可以不用写任何一个if来实现策略的目的，比如我们希望生成一个名字是candy的猫并让她叫一声：

```python
StrategyFactory.get('Cat', 'Candy').call()

output:
Candy: miao miao
```

### 框架中的元类

> 元类就是深度的魔法，99%的⽤户应该根本不必为此操⼼。
> 如果你想搞清楚 究竟是否需要⽤到元类，那么你就不需要它。
> 那些实际⽤到元类的⼈都⾮常 清楚地知道他们需要做什么，⽽且根本不需要解释为什么要⽤元类。
> —— TimPeters

其实元类真正最多的用途在于编写框架，比如Django框架里的ORM定义方式：

```python
class Person(models.Model):
    name = models.CharField(max_length=30)
    age = models.IntegerField()
```

当你创建一个Person对象并且获取age时，系统将返回给你一个int对象，而不是models.IntegerField对象。并且框架同时还可以完成关联字段绑定、生成migration等一系列操作，Django通过复杂的元类定义让整个api变得非常简单易用。

## 探寻类定义

和前面的研究方法一样，我们使用一段简单的代码来研究Python定义类的方式：

```python
class Counter:
    def __init__(self, low, high):
        self.current = low
        self.high = high

    def __iter__(self):
        return self

    def next(self):
        if self.current > self.high:
            raise StopIteration
        else:
            self.current += 1
            return self.current - 1

c = Counter(5, 7)
```