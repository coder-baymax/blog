---
layout:     post
title:      "从图灵机到Cpython - Cpython Internals Notes (1)"
subtitle:   "Cpython虚拟机学习笔记系列"
date:       2019-2-05 12:00:00
author:     "Baymax"
header-img: "img/post-bg-agt-5.jpg"
catalog: true
tags:
    - Python
    - Study Notes
---

> Cpython虚拟机学习笔记系列
> 油管视频：[CPython internals: A ten-hour codewalk](https://pg.ucsd.edu/cpython-internals.htm)
> github博客：[zpoint/CPython-Internals](https://github.com/zpoint/CPython-Internals)
> github源码：[python/cpython](https://github.com/python/cpython)

## 图灵机

其实学校里就有学习过图灵机的相关概念，但是在工作的过程中逐渐忘记了这些内容，直到今天突然刷到了一个知乎问题：[什么是图灵完备](https://www.zhihu.com/question/20115374)，让我突然又对这个概念提起了兴趣。

### 图灵完备

首先，图灵机并不是一种实体的机器，它只是一种抽象概念和数学模型，关于它的描述各种百科都有，可以参考：[Wiki - 图灵机](https://zh.wikipedia.org/wiki/%E5%9B%BE%E7%81%B5%E6%9C%BA)、[百度百科 - 图灵机](https://baike.baidu.com/item/%E5%9B%BE%E7%81%B5%E6%9C%BA)。这里我摘录了百度百科中的相关描述：

1. 一条无限长的纸带 TAPE。纸带被划分为一个接一个的小格子，每个格子上包含一个来自有限字母表的符号，字母表中有一个特殊的符号 表示空白。纸带上的格子从左到右依此被编号为 0，1，2，... ，纸带的右端可以无限伸展。
2. 一个读写头 HEAD。该读写头可以在纸带上左右移动，它能读出当前所指的格子上的符号，并能改变当前格子上的符号。 
3. 一套控制规则 TABLE。它根据当前机器所处的状态以及当前读写头所指的格子上的符号来确定读写头下一步的动作，并改变状态寄存器的值，令机器进入一个新的状态。
4. 一个状态寄存器。它用来保存图灵机当前所处的状态。图灵机的所有可能状态的数目是有限的，并且有一个特殊的状态，称为停机状态。

关于图灵机的描述可能非常复杂难懂，但是图灵证明的结论却非常简单：

> 只要实现了图灵机，就可以用它来解决任何可计算问题。

图灵完备即是说，某个系统实现了图灵机的所有特性，因此这个系统也可以解决任何可计算问题。题外话：知乎上还有一个很有趣的问题：[你无意中发现过哪些图灵完备的系统](https://www.zhihu.com/question/56501530)。

对于一种语言或者系统来说，是不是图灵完备是一种很重要的特性，它意味着这种语言或系统是不是可以解决任何计算问题。现代编程语言，比如：C++、Java、Python等都是图灵完备的。

### 实现图灵机

目前我们在做一些ToB的产品，用于金融行业的数据处理和计算等工作，其实用户的各种需求都可以被解释成“可计算问题”，产品的本质也是创造一种工具去解决用户的“可计算问题”，不过目前这个产品还不是图灵完备的，因为会图灵完备会大大提升用户的使用成本。

上面的知识和思考让我第一次站到了一个语言设计者的视角来观察语言和框架的问题。首先，一种通用编程语言是需要图灵完备的，否则一定会有一些数据结构和算法无法实现，从而不能解决所有的问题。其次，实现图灵机最简单的方法其实是模仿图灵机原本的设计，站在巨人的肩膀上总是没错的，这也从另一个侧面解释了为什么操作系统（C语言运行环境）、JVM和Python虚拟机都有堆、栈等概念，并且是相似的。

有了上面这些背景，在后面学习CPython虚拟机的时候，会有一些常见对象，比如PyObject、FunctionFrame等，其实都可以映射到图灵机中的相关概念。

## Cpython源码

### 运行add.py代码

下面我们写一段非常简单的python代码：

```python
x = 1
y = 2
z = x + y
print z
```

直接使用python运行这段代码，我们可以在屏幕上直接得到结果3，但是执行python的过程其实是一块黑盒：

![](/img/in-post/2019-02-05-cpython-internals-note-1/magic.jpg)

使用过java和python的同学应该会知道，这两个语言都有自己的虚拟机环境，并且是会有编译的过程的，其中java会形成很多class文件，而python会形成pyc文件。

因此我们从顶层的视角来看，可以把整个运行流程进行拆分，变成两个步骤：

1. 通过编译器将py文件编译成虚拟机的可执行文件
2. 将编译好的bytecode传入虚拟机执行，得到输出结果

![](/img/in-post/2019-02-05-cpython-internals-note-1/magic-2.jpg)

对于编译器这部分原理不是这次讨论的主要内容，如果对这部分有兴趣可以找编译原理相关的学习资料，Cpython相关的学习主要针对虚拟机的部分。

### 查看bytecode

为了方便跟进油管上的学习资料，我直接下载了cpython2.7.8的源代码，可以直接在github的cpython库中找到对应的tag。下载好源码之后进行本地编译：

```bash
bash configure
make
```

通过执行下面的python代码，获取add.py的bytecode：

```python
with open('add.py', 'r') as f:
    c = compile(f.read(), 'add.py', 'exec')
    print [ord(x) for x in c.co_code]
```

上面这段代码我们将add.py中所有的代码进行了编译，并且转化成ascii码打印到屏幕上，结果是一串数字，我们很难从中看到什么内容：

```python
[100, 0, 0, 90, 0, 0, 100, 1, 0, 90, 1, 0, 101, 0, 0, 101, 1, 0, 23, 90, 2, 0, 101, 2, 0, 71, 72, 100, 2, 0, 83]
```

不过python本身提供了更人性化的bytecode查看工具：[dis](https://docs.python.org/2.7/library/dis.html)，我们执行：

```bash
./python -m dis add.py
```

可以得到python帮我们格式化好的bytecode：

```bash
  1           0 LOAD_CONST               0 (1)
              3 STORE_NAME               0 (x)

  2           6 LOAD_CONST               1 (2)
              9 STORE_NAME               1 (y)

  3          12 LOAD_NAME                0 (x)
             15 LOAD_NAME                1 (y)
             18 BINARY_ADD
             19 STORE_NAME               2 (z)

  4          22 LOAD_NAME                2 (z)
             25 PRINT_ITEM
             26 PRINT_NEWLINE
             27 LOAD_CONST               2 (None)
             30 RETURN_VALUE
```

### 寻找opcode

对于python熟悉的同学可能知道eval函数，使用这个函数可以动态执行python代码，在源代码中，最主要的执行代码就在目录：Python/ceval.c中，该文件的头部有几个引用：

```cpp
#include "Python.h"

#include "code.h"
#include "frameobject.h"
#include "eval.h"
#include "opcode.h"
#include "structmember.h"
```

其中opcode.h文件就对应了上面使用dis出来的方法编码，我找了add.py中涉及到的所有opcode：

```cpp
#define BINARY_ADD	23
#define PRINT_ITEM	71
#define PRINT_NEWLINE	72
#define RETURN_VALUE	83
#define STORE_NAME	90	/* Index in name list */
#define LOAD_CONST	100	/* Index in const list */
#define LOAD_NAME	101	/* Index in name list */
```

结合opcode的定义我们不难看出，这些和前面打印的ascii码数组是可以一一对应的，每一个opcode都占用了一个字符的位置，另外还填充了参数信息。

### 巨大的无限循环

在ceval.c源代码的964行，我们可以看到一个巨大的for loop：

```cpp
964    for (;;) {...}
```

在1112行，我们可以看到一个巨大的switch：

```cpp
1112        switch (opcode) {...}
```

这样看下来cpython虚拟机的本质就很清晰了，它有一个巨大的无限循环，每次从bytecode中取出一个opcode来执行，当然根据opcode的要求不同，还会从后面的bytecode中拿到相应的参数。

按照图灵机的定义，光有无限的纸带和控制规则是不够的，我们还需要有一个状态寄存器。源代码中的LOAD_CONST就正好涉及到了这部分内容：

```cpp
case LOAD_CONST:
    x = GETITEM(consts, oparg);
    Py_INCREF(x);
    PUSH(x);
    goto fast_next_opcode;
```

这几个操作都比较简单，分别是：

1. 从consts中获取对应常量，并存到x中
2. 增加x的引用计数，用于垃圾回收
3. PUSH(x)，对应一个压栈操作
4. 快速跳转，执行下一个opcode

对于PUSH的定义，我们在代码的头部就可以看到：

```cpp
register PyObject **stack_pointer;  /* Next free slot in value stack */
#define BASIC_PUSH(v)     (*stack_pointer++ = (v))
#define PUSH(v)         { (void)(BASIC_PUSH(v), \
                          lltrace && prtrace(TOP(), "push")); \
                          assert(STACK_LEVEL() <= co->co_stacksize); }
```

从这里我们可以很明显的看到stack_pointer对应了一个栈指针，这个栈里面保存的都是PyObject类型的对象，后面的章节我们会看到PyObject是Python中最重要的对象类型之一。

另外有两个PUSH函数，其中BASIC_PUSH只将一个对象压栈，而PUSH函数在压栈的同时，还执行了栈大小的检查，防止栈溢出。

### 再看bytecode

我们根据一部分源码的阅读，再来看add.py的bytecode，就会发现整体逻辑变得清晰：

1. 载入1和2两个常量，分别存入x和y，载入常量时压栈，存入变量时出栈
2. 获取x和y的值，并执行add操作，将结果存入z
3. 打印z的值和回车符号
4. 载入常量None，并作为返回值进行返回

至此，我们可以在脑海中大致的勾画出cpython运行代码的轮廓了，执行一段python代码可以看作图灵机的运行过程，其中所有的操作符和状态在Cpython虚拟机中已经提前定义好了，而巨大的循环就像一根无限长的纸带，可以方便的在状态之间进行转换。

## 预告

这一章节到这里就结束啦，有兴趣的话可以继续阅读下一章：**方法帧、调用和作用域**。