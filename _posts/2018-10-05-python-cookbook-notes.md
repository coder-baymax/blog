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

这本书和一般的语言书在结构上有非常大的不同，主要是由于这本书是摘录了论坛里面精华的内容，所以书上的内容相对割裂，在查找的时候比较困难。这一篇博客主要是做一个常用技巧的收录，方便直接查找要用的工具。

### 工具

#### 快速实现小根堆

一般来说堆这种数据结构会应用于优先队列，在python和java中都有对应的工具类，python中的是：queue.PriorityQueue，这是一个线程安全的优先队列。

python标准库还提供了额外的库来直接使用数组实现一个堆，应对K最小、K最大问题时会非常有效。

```python
import heapq
import random

nums = [random.randint(-100, 100) for x in range(20)]
heapq.heapify(nums)
print([heapq.heappop(nums) for x in range(20)])

output:
[-95, -87, -82, -79, -50, -48, -45, -45, -44, -27, -22, -1, 0, 1, 6, 9, 72, 85, 95, 96]
```

详细的内容可以参考官方的文档：[heapq — Heap queue algorithm](https://docs.python.org/3/library/heapq.html)。文档中还特别写明了heapify的时间复杂度是线性的，晚点有兴趣的时候可以看一下是如何实现的。

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

详细的内容可以参考官方的文档：[collections — Container datatypes](https://docs.python.org/3/library/collections.html?collections.Counter)。同时该容器还提供了most_common用于返回最常见的N个对象。

#### 字符串替换

最简单的方式是使用replace函数来进行替换，这无需多言。相对复杂的方式是使用正则来进行替换，正则替换对应的函数是re.sub，该函数包含了三个参数，分别是：

1. 匹配的模式字符串，和其他正则一样，用()来表示一个组
2. 替换模式字符串，其中用反斜杠数字的表示第几组，比如\1\2
3. 等待替换内容的字符串

这样解释起来依旧抽象，我们写一个日期转换的例子，把2000-05-03转化成2000年05月03日：

```python
import re

date_str = '2000-05-03'
date_str = re.sub(r'(\d{4})-(\d{2})-(\d{2})', r'\1年\2月\3日', date_str)
print(date_str)

output:
2000年05月03日
```

在使用时别忘了正则字符串都要加入r开头作为识别标签，另外如果需要重复使用匹配的模式字符串，可以使用re.compile提前编译来提升效率。更多用法可以参考官方文档：[re — Regular expression operations — re.sub](https://docs.python.org/3/library/re.html?#re.sub)。

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

#### 

### 设计

#### 用re模块实现一个文本解析器

在做文本处理的时候，我们可能会需要在一堆有特定格式的字符串中，找到对应的操作信息，并根据信息做出响应，比如说，我们需要将这个字符串：

```python
foo = 23 + 43 * 10
```

解析成一个操作令牌的列表：

```python
[('name', 'foo'), ('eq', '='), ('num', '23'), ('plus', '+'), ('num', '43'), ('times', '*'), ('num', '10')]
```

我们可以使用一些带有命名的正则捕获组来定义所有可能的模式，并且使用re.finditer方法来匹配每一种模式，代码如下：

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

文本解析是一个很大的主题，也是编译原理基础的一部分，这部分内容在官方文档中也有相应介绍：[re — Regular expression operations — writing a tokenizer](https://docs.python.org/3/library/re.html?#writing-a-tokenizer)。如果说只需要解析一个计算+函数的表达式的话，还有一种专用算法：[wiki — 调度场算法](https://zh.wikipedia.org/zh-cn/%E8%B0%83%E5%BA%A6%E5%9C%BA%E7%AE%97%E6%B3%95)。