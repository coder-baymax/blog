---
layout:     post
title:      "Python Cookbook Notes - Python技巧学习笔记"
subtitle:   "Cookbook中的技巧实在太多了，收录一些平时用的上的技巧"
date:       2018-10-05 12:00:00
author:     "Baymax"
header-img: "img/post-bg-agt-11.jpg"
catalog: true
tags:
    - Python
    - Study Notes
---

## Python Cookbook

这本书和一般的语言书在结构上有非常大的不同，因为这本书是摘录了论坛里面精华的内容，所以书上的内容相对割裂，在查找的时候比较困难。这一篇博客主要是结合自己的日常开发，做一个常用技巧的收录，方便直接查找要用的工具。

### 工具

#### 快速实现小根堆

一般来说堆这种数据结构会应用于优先队列，在python和java中都有对应的工具类，python中的是：queue.PriorityQueue，这是一个线程安全的优先队列。

另外，python标准库还提供了额外的库来直接使用数组实现一个堆，应对K最小、K最大问题时会非常有效。

```python
import heapq
import random

nums = [random.randint(-100, 100) for x in range(20)]
heapq.heapify(nums)
print([heapq.heappop(nums) for x in range(20)])

output:
[-95, -87, -82, -79, -50, -48, -45, -45, -44, -27, -22, -1, 0, 1, 6, 9, 72, 85, 95, 96]
```

详细的内容可以参考官方文档：[heapq — Heap queue algorithm](https://docs.python.org/3/library/heapq.html)。文档中还特别写明了heapify的时间复杂度是线性的，未来有兴趣的时候可以看一下是如何实现的。

#### 使用zip连接多个数组

如果想要将多个数组里面的内容一一对应地组合起来时，可以使用zip()函数。

```python
x = [1, 2, 3]
y = [4, 5, 6]
z = [7, 8, 9]
for a in zip(x, y, z):
    print(a)

output:
(1, 4, 7)
(2, 5, 8)
(3, 6, 9)
```

#### 使用Counter统计每个元素的出现次数

很多时候需要统计一个列表中的单词或者元素出现次数，一般会用for语句来写，使用迭代器似乎没有很好的写法，这里推荐系统自带的collections.Counter容器。

```python
import random
from collections import Counter

x = [random.randint(0, 5) for _ in range(50)]
counter = Counter(x)
print(counter)

output:
Counter({0: 13, 3: 12, 4: 8, 1: 6, 2: 6, 5: 5})
```

详细的内容可以参考官方文档：[collections — Container datatypes](https://docs.python.org/3/library/collections.html?collections.Counter)，同时该容器还提供了most_common用于返回最常见的N个对象。

#### 正则字符串替换

最简单的字符串替换方式是使用replace函数来进行替换，这无需多言。相对复杂的方式是使用正则来进行替换，正则替换对应的函数是re.sub，该函数包含了三个参数，分别是：

1. 匹配的模式字符串，和其他正则一样，用()来表示一个组
2. 替换模式字符串，其中用反斜杠数字的表示第几组，比如\1\2
3. 待替换内容的字符串

这样解释起来依旧抽象，我写一个日期转换的例子，把2000-05-03转化成2000年05月03日：

```python
import re

date_str = '2000-05-03'
date_str = re.sub(r'(\d{4})-(\d{2})-(\d{2})', r'\1年\2月\3日', date_str)
print(date_str)

output:
2000年05月03日
```

在使用时别忘了正则字符串要加上r开头作为识别标签，另外如果需要重复使用匹配的模式字符串，可以使用re.compile提前编译来提升效率，更多用法可以参考官方文档：[re — Regular expression operations — re.sub](https://docs.python.org/3/library/re.html?#re.sub)。

#### 在python中表达正负无穷和非数字浮点数

在python中可以直接用float来创建相关数值：

```python
x = float("-inf")
y = float("inf")
z = float("nan")

print(x, y, z, x < y)

output:
-inf inf nan True
```

#### 使用yield from拍平嵌套数组

yield from是一个生成器语法，其实日常开发中很少用到，但是在某些特定的情况下会让代码显得非常清晰，比如希望拍平一个多层嵌套的数组：[1, 2, 3, [4, 5], [6, [7, [8]]]]，希望能获得：[1,2,3,4,5,6,7,8]，可以使用如下方法：

```python
def flat(nums):
    if isinstance(nums, list):
        for x in nums:
            yield from flat(x)
    else:
        yield nums


array = [1, 2, 3, [4, 5], [6, [7, [8]]]]
print(list(flat(array)))

output:
[1, 2, 3, 4, 5, 6, 7, 8]
```

#### 使用csv系统库读取csv文件

一般处理csv文件的时候，我们会习惯用逗号作为分隔符来处理，但是系统其实提供了一种更易用的csv库来专门处理这一项内容：

```python
import csv
from pprint import pprint
from collections import namedtuple
from tempfile import TemporaryFile

with TemporaryFile("w+t") as f:
    f.write("年份,人数,报课数,单价,总收入\n")
    f.write("1,250,300,4500,1350000\n")
    f.write("2,350,400,4500,1800000\n")

    f.seek(0)
    f_csv = csv.reader(f)
    headers = next(f_csv)
    Row = namedtuple("Row", headers)
    rows = [Row(*r) for r in f_csv]
    pprint(rows)

output:
[Row(年份='1', 人数='250', 报课数='300', 单价='4500', 总收入='1350000'),
 Row(年份='2', 人数='350', 报课数='400', 单价='4500', 总收入='1800000')]
```

上面的例子中另外用到的几个小工具：

- **TemporaryFile**：用于生成一个临时文件
- **namedtuple**：用于自定义一个带参数名的元组类
- **pprint**：在打印内容比较复杂的情况下代替print函数，可以获得一个比较好的打印效果

#### 


### 设计

#### 用re模块实现一个文本解析器

在做文本处理的时候，可能要在一堆有特定格式的字符串中，进行模式匹配，找到对应的操作信息，并根据信息做出响应，比如说，我们需要将这个字符串：

```python
foo = 23 + 43 * 10
```

解析成一个操作令牌的列表：

```python
[('name', 'foo'), ('eq', '='), ('num', '23'), ('plus', '+'), ('num', '43'), ('times', '*'), ('num', '10')]
```

这时可以使用一些带有命名的正则捕获组来定义所有可能的令牌，并且使用re.finditer方法来匹配每一种令牌，代码如下：

```python
import re
from collections import namedtuple

NAME = r"(?P<name>[a-zA-Z_][a-zA-Z_0-9]+)"
NUM = r'(?P<num>\d+)'
PLUS = r'(?P<plus>\+)'
TIMES = r'(?P<times>\*)'
EQ = r'(?P<eq>=)'
WS = r'(?P<ws>\s+)'

pattern = re.compile('|'.join([NAME, NUM, PLUS, TIMES, EQ, WS]))
op_str = 'foo = 23 + 43 * 10'
Token = namedtuple('Token', ['type', 'value'])
tokens = (Token(x.lastgroup, x.group()) for x in pattern.finditer(op_str))
print([x for x in tokens if x.type != 'ws'])

output:
[Token(type='name', value='foo'), Token(type='eq', value='='), Token(type='num', value='23'), Token(type='plus', value='+'), Token(type='num', value='43'), Token(type='times', value='*'), Token(type='num', value='10')]
```

文本解析是一个很大的主题，也是编译原理基础的一部分，这部分内容在官方文档中也有相应介绍：[re — Regular expression operations — writing a tokenizer](https://docs.python.org/3/library/re.html?#writing-a-tokenizer)。如果说只需要解析一个运算符和函数的表达式的话，还有一种专用算法：[wiki — 调度场算法](https://zh.wikipedia.org/zh-cn/%E8%B0%83%E5%BA%A6%E5%9C%BA%E7%AE%97%E6%B3%95)。

#### 使用cached_property使类属性自动缓存

使用系统自带的property装饰器可以将一个成员方法转化为属性，但是这么做的话每次使用这个属性都会调用相应的方法，如果这个方法本身比较耗时，那么计算一次以后自动缓存会是一个好方法。

在python的3.8版本以前，并没有官方库的支持。如果项目中使用了django的话，可以用django.utils.functional下面的cached_property装饰器，但是在python3.8以后，cached_property已经被合入到官方库，我们可以直接使用官方提供的装饰器：

```python
import time
from functools import cached_property
from threading import Thread


class Foo:
    def __init__(self):
        self.count = 0

    @cached_property
    def bar(self):
        time.sleep(0.5)
        self.count += 1
        return self.count


f = Foo()
threads = []
for x in range(10):
    t = Thread(target=lambda: f.bar)
    t.start()
    threads.append(t)
for t in threads:
    t.join()
print(f.bar)

output:
1
```

上面这段代码还检查了cached_property是否是线程安全的，如果将cached_property的引用改为：

```python
from django.utils.functional import cached_property
```

那么我们会得到的输出是10，这说明django的cached_property并不是线程安全的，其实很多第三方库的cached_property都不是线程安全的，因此在多线程情况下尽量使用官方库中的cached_property，以免出现意外bug。

#### 使用元类构建注册工厂

注册工厂是一个比较常见的设计模式，尤其在快速迭代的项目中，如果已经实现设计好一个抽象模型，在添加新功能时往往会用到。在python中我们可以使用元类让新功能自动注册到工厂中去，这样我们在添加新功能时，只需要继承某一个基类就可以完成自动加载。

```python
class Factory:
    workers = {}

    @classmethod
    def build(cls, name):
        return cls.workers[name]().build()


class WorkerMeta(type):
    def __new__(mcs, what, bases=None, attrs=None):
        new_class = super().__new__(mcs, what, bases, attrs)
        if what != "Worker":
            Factory.workers[what.replace("Worker", "").lower()] = new_class
        return new_class


class Worker(metaclass=WorkerMeta):
    pass


class CarWorker(Worker):
    def build(self):
        return "super car"


class PlaneWorker(Worker):
    def build(self):
        return "super plane"


print(Factory.build("car"))
print(Factory.build("plane"))

output:
super car
super plane
```

在上面的例子中，如果需要给现有工厂新增功能，仅需要写一个新的类继承Worker即可，不会对现有代码造成任何入侵。

另外，使用元类还可以对新类进行各种操作，这在实现类库或者中间件的时候尤为方便，在未来实现中间件的时候，可以参考一下Django类库中models的继承结构：

```python
class ModelBase(type):
    """Metaclass for all models."""
    def __new__(cls, name, bases, attrs, **kwargs):
        super_new = super().__new__
	    ...


class Model(metaclass=ModelBase):
    def __init__(self, *args, **kwargs):
	    ...
```