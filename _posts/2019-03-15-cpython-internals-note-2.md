---
layout:     post
title:      "global标识符与方法调用 - Cpython Internals Notes (2)"
subtitle:   "Cpython虚拟机学习笔记系列"
date:       2019-3-15 12:00:00
author:     "Baymax"
header-img: "img/post-bg-agt-2.jpg"
catalog: true
tags:
    - Python
    - Study Notes
---

> Cpython虚拟机学习笔记系列  
> 油管视频：[CPython internals: A ten-hour codewalk](https://pg.ucsd.edu/cpython-internals.htm)  
> github博客：[zpoint/CPython-Internals](https://github.com/zpoint/CPython-Internals)  
> github源码：[python/cpython](https://github.com/python/cpython)  

## global标识符

在之前的工作中，基于其他语言的经验，我曾经写过类似下面的代码：

```python
x = 0
def func():
    x += 1
    print("func:", x)

func()
print("global:", x)
```

这段代码的运行结果会让人感到疑惑，因为它是没法正常运行的，会直接报错：

```bash
Traceback (most recent call last):
  File "TEST/nonlocal2.py", line 6, in <module>
    func()
  File "TEST/nonlocal2.py", line 3, in func
    x += 1
UnboundLocalError: local variable 'x' referenced before assignment
```

在StackOverflow搜索一番之后可以找到下面的答案，通过给变量x增加一个global标识后我们就可以得到想要的结果了：

```python
x = 0
def func():
    global x
    x += 1
    print("func:", x)

func()
print("global:", x)

output：
func: 1
global: 1
```

但是global就会有一个副作用：x就直接变成全局变量了，在某些场景下可能并不希望有这样的效果。目前在python2中没有更好的解决方案，在python3中新增了nonlocal标识符，用于表示某个变量继承于外层的作用域，相关文档：[Python Document - The global statement](https://docs.python.org/3/reference/simple_stmts.html#the-global-statement)。

## 