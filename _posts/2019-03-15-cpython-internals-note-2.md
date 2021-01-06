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

## 变量作用域

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
  File "TEST/global.py", line 6, in <module>
    func()
  File "TEST/global.py", line 3, in func
    x += 1
UnboundLocalError: local variable 'x' referenced before assignment
```

### global标识符

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

## 解构python的函数运行

为了了解python函数运行的方式，我们编写一段demo代码：

```python
x = 10

def foo(x):
    y = x * 2
    return bar(y)

def bar(x):
    y = x / 2
    return y

print foo(x)
```

和之前的博客一样，使用python自带的dis模块来解释这段代码，我们可以得到下面的内容：

```bash
  1           0 LOAD_CONST               0 (10)
              3 STORE_NAME               0 (x)

  3           6 LOAD_CONST               1 (<code object foo at 0x7f7191185a30, file "TEST/func.py", line 3>)
              9 MAKE_FUNCTION            0
             12 STORE_NAME               1 (foo)

  7          15 LOAD_CONST               2 (<code object bar at 0x7f7191185830, file "TEST/func.py", line 7>)
             18 MAKE_FUNCTION            0
             21 STORE_NAME               2 (bar)

 11          24 LOAD_NAME                1 (foo)
             27 LOAD_NAME                0 (x)
             30 CALL_FUNCTION            1
             33 PRINT_ITEM
             34 PRINT_NEWLINE
             35 LOAD_CONST               3 (None)
             38 RETURN_VALUE
```

### 可视化运行工具

对于上面的bytecode会比较难以阅读，不过还有一些可视化工具帮助我们研究：[Python Tutor](http://pythontutor.com/visualize.html#mode=edit)。把代码复制黏贴进去之后，可以看到每一步运行时，python虚拟机的状态。

![](/img/in-post/2019-03-15-cpython-internals-note-2/tutor.gif)

从上面的动图可以看到，整段代码经历了三个方法的调用，每次方法调用会将一个frame（方法帧）压入调用栈：

1. 初始化代码，有三个全局变量，分别是x（一个int值），foo（一个方法）和bar（另一个方法）
2. 调用foo方法，将x传入，foo的方法帧内保存了x的局部变量，计算得到y的值
3. 调用bar方法，将y传入，作为bar方法帧内的x局部变量，计算返回y的值，逐层返回后打印

### 再看bytecode

对比上一章节，这一章节中新增了几个与方法有关的opcode，主要是MAKE_FUCNTION和CALL_FUNCTION。

#### MAKE_FUNCTION

首先是MAKE_FUNCTION，这个opcode看名字应该能猜到它的意思了，它用于创建并返回一个code object，用来保存方法的内容，在cevel源代码中，是这样的：

```cpp
case MAKE_FUNCTION:
    v = POP(); /* code object */
    x = PyFunction_New(v, f->f_globals);
    Py_DECREF(v);
    /* XXX Maybe this should be a separate opcode? */
    if (x != NULL && oparg > 0) {
        v = PyTuple_New(oparg);
        if (v == NULL) {
            Py_DECREF(x);
            x = NULL;
            break;
        }
        while (--oparg >= 0) {
            w = POP();
            PyTuple_SET_ITEM(v, oparg, w);
        }
        err = PyFunction_SetDefaults(x, v);
        Py_DECREF(v);
    }
    PUSH(x);
    break;
```

这里面乍一看似乎有很多魔法，但是方法的命名还是非常规范的，大部分内容都可以猜到意思，除了两个全局的内容：

1. 