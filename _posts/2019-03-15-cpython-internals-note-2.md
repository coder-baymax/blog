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

在StackOverflow搜索一番之后可以找到下面的答案，通过给变量x增加一个global标识就可以正常运行了：

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

但是global就会有一个副作用：x直接变成全局变量了，这会对全局变量造成污染，在某些场景下可能并不希望有这样的效果。目前在python2中没有更好的解决方案，在python3中新增了nonlocal标识符，用于表示某个变量继承于外层的作用域，相关文档：[Python Document - The global statement](https://docs.python.org/3/reference/simple_stmts.html#the-global-statement)。

## 解构python的函数运行

为了解构python函数运行的方式，我编写了一段demo代码：

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

和之前的博客一样，使用python自带的dis模块来解释这段代码，可以得到下面的内容：

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

上面的bytecode会比较难以理解，不过还有一些可视化工具帮助研究：[Python Tutor](http://pythontutor.com/visualize.html#mode=edit)。把代码复制黏贴进去之后，可以看到每一步运行时，python虚拟机的状态。

![](/img/in-post/2019-03-15-cpython-internals-note-2/tutor.gif)

从上面的动图可以看到，整段代码经历了三个方法的调用，每次方法调用会将一个frame（方法帧）压入调用栈：

1. 初始化代码，有三个全局变量，分别是x（一个int值），foo（一个方法）和bar（另一个方法）
2. 调用foo方法，将x传入，foo的方法帧内保存了x的局部变量，计算得到y的值
3. 调用bar方法，将y传入，作为bar方法帧内的x局部变量，计算返回y的值，逐层返回后打印

### 再看bytecode

对比上一章节，这一章节中新增了几个与方法有关的opcode，主要是MAKE_FUCNTION和CALL_FUNCTION。

### MAKE_FUNCTION

首先是MAKE_FUNCTION，这个opcode看名字应该能猜到它的意思了，它用于创建并返回一个PyFunctionObject，用来保存方法的内容，在cevel源代码中，是这样的：

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

可以看到核心代码是抛开注释代码以及后面判断的部分，注释的内容是：“也许这段内容应该被放到另外一个opcode中去？”，简单看下if里面的这段代码，其中PyTuple之前已经介绍过，是对一个数组的封装，在python中对应了Tuple类型，PyFunction_SetDefaults这个方法从名字可以猜测应该和默认参数有关，一会再来详细看这个方法的内容。

和函数相关的方法调用主要有两个：PyFunction_New和PyFunction_SetDefaults，它们的申明都在funcobject.h中，定义都在funcobject.c中，直接来看源码。

#### PyFunction_New方法

这个方法看名称就可以猜到应该是创建一个新的函数对象，参数有两个：code和globals，代表代码块和全局变量的引用。

```cpp
PyObject *
PyFunction_New(PyObject *code, PyObject *globals)
{
    PyFunctionObject *op = PyObject_GC_New(PyFunctionObject,
                                        &PyFunction_Type);
    static PyObject *__name__ = 0;
    if (op != NULL) {
        PyObject *doc;
        PyObject *consts;
        PyObject *module;
        op->func_weakreflist = NULL;
        Py_INCREF(code);
        op->func_code = code;
        Py_INCREF(globals);
        op->func_globals = globals;
        op->func_name = ((PyCodeObject *)code)->co_name;
        Py_INCREF(op->func_name);
        op->func_defaults = NULL; /* No default arguments */
        op->func_closure = NULL;
        consts = ((PyCodeObject *)code)->co_consts;
        if (PyTuple_Size(consts) >= 1) {
            doc = PyTuple_GetItem(consts, 0);
            if (!PyString_Check(doc) && !PyUnicode_Check(doc))
                doc = Py_None;
        }
        else
            doc = Py_None;
        Py_INCREF(doc);
        op->func_doc = doc;
        op->func_dict = NULL;
        op->func_module = NULL;

        /* __module__: If module name is in globals, use it.
           Otherwise, use None.
        */
        if (!__name__) {
            __name__ = PyString_InternFromString("__name__");
            if (!__name__) {
                Py_DECREF(op);
                return NULL;
            }
        }
        module = PyDict_GetItem(globals, __name__);
        if (module) {
            Py_INCREF(module);
            op->func_module = module;
        }
    }
    else
        return NULL;
    _PyObject_GC_TRACK(op);
    return (PyObject *)op;
}
```

这段代码比较简单，大部分都是赋值和初始化操作，比较有趣的部分有几个：

1. PyObject_GC_New看名字就可以猜到和内存管理有关，这个方法定义在gcmodule.c中，作用是基于传入的类型申请对应大小的内存空间，再深入的话会涉及到python的内存管理模型，因此这个函数了解到这就可以了
2. \__name\__这个魔法字段在某些特殊的情况下会使用到，针对所有的方法都有效，在这部分源代码中保证了Function对象必须存在\__name\__字段，否则就初始化失败了
3. 函数的module信息也是直接存在函数中的，并且是通过全局变量的dict对象获取的

代码的最后将PyFunctionObject对象强转为PyObject对象再返回。

#### PyFunction_SetDefaults方法

该方法用于设置方法的默认参数：

```cpp
int
PyFunction_SetDefaults(PyObject *op, PyObject *defaults)
{
    if (!PyFunction_Check(op)) {
        PyErr_BadInternalCall();
        return -1;
    }
    if (defaults == Py_None)
        defaults = NULL;
    else if (defaults && PyTuple_Check(defaults)) {
        Py_INCREF(defaults);
    }
    else {
        PyErr_SetString(PyExc_SystemError, "non-tuple default args");
        return -1;
    }
    Py_XDECREF(((PyFunctionObject *) op) -> func_defaults);
    ((PyFunctionObject *) op) -> func_defaults = defaults;
    return 0;
}
```

这一段代码还是比较容易理解的，只是对默认参数进行了一些检查之后，加上了引用计数，就传入了对应的PyFunctionObject作为默认参数。结合上面MAKE_FUNCTION的代码可以看到，这里传入的defaults参数是在外部调用的时候传递进来，并且在这里赋值的，这样做会引发一个经典问题，来看一段代码。

```python
def foo(num, x=[]):
    x.append(num)
    return x

print foo(1)
print foo(2)

output:
[1]
[1, 2]
```

这个bug我之前写代码的时候也曾经遇到过，因为在没有了解python默认参数实现细节之前，会认为默认参数是调用函数时生效的，但是看过上面源码就会知道，默认参数实际上是在函数申明时绑定的，并且绑定的还是一个全局变量。

因此，在《Python Cookbook》中也不建议在默认参数中使用对象：[定义有默认参数的函数](https://python3-cookbook.readthedocs.io/zh_CN/latest/c07/p05_define_functions_with_default_arguments.html)，这样会给代码造成各种麻烦，不仅在函数内，如果作为返回的话，这返回的其实是一个全局变量，会导致牵一发动全身。

### CALL_FUNCTION

这个opcode用于调用函数，这一段代码本身还是比较简单的：

```cpp
case CALL_FUNCTION:
{
    PyObject **sp;
    PCALL(PCALL_ALL);
    sp = stack_pointer;
#ifdef WITH_TSC
    x = call_function(&sp, oparg, &intr0, &intr1);
#else
    x = call_function(&sp, oparg);
#endif
    stack_pointer = sp;
    PUSH(x);
    if (x != NULL)
        continue;
    break;
}
```

这段代码中的stack_pointer是我们的老朋友了，在call_function之前使用sp保存了栈顶位置，并且在call_function之后进行恢复。需要注意的是，在python中的方法是很多种的，除了一般的Function之外，还有Object中的Method以及python内部的C语言函数，这些函数都会使用CALL_FUNCTION来调用，然后再来看源码中的call_function方法。

#### call_function方法

```cpp
static PyObject *
call_function(PyObject ***pp_stack, int oparg
#ifdef WITH_TSC
                , uint64* pintr0, uint64* pintr1
#endif
                )
{
    int na = oparg & 0xff;
    int nk = (oparg>>8) & 0xff;
    int n = na + 2 * nk;
    PyObject **pfunc = (*pp_stack) - n - 1;
    PyObject *func = *pfunc;
    PyObject *x, *w;

    /* Always dispatch PyCFunction first, because these are
       presumed to be the most frequent callable object.
    */
    if (PyCFunction_Check(func) && nk == 0) {
        ...
    } else {
        if (PyMethod_Check(func) && PyMethod_GET_SELF(func) != NULL) {
            /* optimize access to bound methods */
            PyObject *self = PyMethod_GET_SELF(func);
            PCALL(PCALL_METHOD);
            PCALL(PCALL_BOUND_METHOD);
            Py_INCREF(self);
            func = PyMethod_GET_FUNCTION(func);
            Py_INCREF(func);
            Py_DECREF(*pfunc);
            *pfunc = self;
            na++;
            n++;
        } else
            Py_INCREF(func);
        READ_TIMESTAMP(*pintr0);
        if (PyFunction_Check(func))
            x = fast_function(func, pp_stack, n, na, nk);
        else
            x = do_call(func, pp_stack, na, nk);
        READ_TIMESTAMP(*pintr1);
        Py_DECREF(func);
    }

    /* Clear the stack of the function object.  Also removes
       the arguments in case they weren't consumed already
       (fast_function() and err_args() leave them on the stack).
     */
    while ((*pp_stack) > pfunc) {
        w = EXT_POP(*pp_stack);
        Py_DECREF(w);
        PCALL(PCALL_POP);
    }
    return x;
}
```

这段代码很长，可以看到首先是计算出func和参数所在的位置；然后针对传入的函数类型进行类判断，第一段判断中的注释有说明：总是先检查函数是不是PyCFunction（系统内建的函数）类型的，因为这是最常见的函数类型。不过现在需要关注的是PyFunction类型，即一般的函数类型，在这种判断下直接调用了fast_function方法。


#### fast_function方法

```cpp
static PyObject *
fast_function(PyObject *func, PyObject ***pp_stack, int n, int na, int nk)
{
    PyCodeObject *co = (PyCodeObject *)PyFunction_GET_CODE(func);
    PyObject *globals = PyFunction_GET_GLOBALS(func);
    PyObject *argdefs = PyFunction_GET_DEFAULTS(func);
    PyObject **d = NULL;
    int nd = 0;

    PCALL(PCALL_FUNCTION);
    PCALL(PCALL_FAST_FUNCTION);
    if (argdefs == NULL && co->co_argcount == n && nk==0 &&
        co->co_flags == (CO_OPTIMIZED | CO_NEWLOCALS | CO_NOFREE)) {
        ...
    }
    if (argdefs != NULL) {
        d = &PyTuple_GET_ITEM(argdefs, 0);
        nd = Py_SIZE(argdefs);
    }
    return PyEval_EvalCodeEx(co, globals,
                             (PyObject *)NULL, (*pp_stack)-n, na,
                             (*pp_stack)-2*nk, nk, d, nd,
                             PyFunction_GET_CLOSURE(func));
}
```

在这里终于可以找到开篇那个bug的答案了，这个答案由几个部分组成：

1. 首先是针对globals的使用，这里globals是作为一个参数传递给PyEval_EvalCodeEx方法的，这个方法就是包含巨大for loop的方法运行函数
2. 调用PyEval_EvalCodeEx方法时，会使用PyFrame_New方法创建一个新的方法帧作为运行该方法的环境，并保存传入的globals引用

因此如果在函数内部直接使用全局变量，那么都是拿到全局变量的引用，而不是全局变量本身，对于调用对象的方法、修改对象成员这些操作都是能正常执行的，比如下面的代码就可以正常运行：

```python
nums = []

def update(i):
    nums.append(i)

update(1)
update(2)
print nums

output:
[1, 2]
```

但是像这篇博客开头那样的代码就不能正常运行，因为x += 1本质上包含了y = x + 1和x = y两个部分，而直接覆盖引用的值也没办法修改原对象，所以python在执行这段代码的时候就直接报错了，必须显式告诉python解释器这个变量的意义才可以正常运行代码。

#### 题外话：PCALL和WITH_TSC

这两个参数的作用各种参考文档里面并没有提及，我阅读了一下相关代码得到了一些猜测。首先是PCALL方法：

```cpp
static int pcall[PCALL_NUM];

#define PCALL_ALL 0
#define PCALL_FUNCTION 1
#define PCALL_FAST_FUNCTION 2
#define PCALL_FASTER_FUNCTION 3
#define PCALL_METHOD 4
#define PCALL_BOUND_METHOD 5
#define PCALL_CFUNCTION 6
#define PCALL_TYPE 7
#define PCALL_GENERATOR 8
#define PCALL_OTHER 9
#define PCALL_POP 10

/* Notes about the statistics

   PCALL_FAST stats

   FAST_FUNCTION means no argument tuple needs to be created.
   FASTER_FUNCTION means that the fast-path frame setup code is used.

   If there is a method call where the call can be optimized by changing
   the argument tuple and calling the function directly, it gets recorded
   twice.

   As a result, the relationship among the statistics appears to be
   PCALL_ALL == PCALL_FUNCTION + PCALL_METHOD - PCALL_BOUND_METHOD +
                PCALL_CFUNCTION + PCALL_TYPE + PCALL_GENERATOR + PCALL_OTHER
   PCALL_FUNCTION > PCALL_FAST_FUNCTION > PCALL_FASTER_FUNCTION
   PCALL_METHOD > PCALL_BOUND_METHOD
*/

#define PCALL(POS) pcall[POS]++

PyObject *
PyEval_GetCallStats(PyObject *self)
{
    return Py_BuildValue("iiiiiiiiiii",
                         pcall[0], pcall[1], pcall[2], pcall[3],
                         pcall[4], pcall[5], pcall[6], pcall[7],
                         pcall[8], pcall[9], pcall[10]);
}
#else
#define PCALL(O)
```

这个参数的作用是针对python内部不同类型函数调用的次数进行统计，每次调用函数的时候都会调用对应的PCALL，最后这个东西会存放到python的sys.callstats中，这在某些profile中可能会用到。

另外一个就是WITH_TSC定义了，在call_function里面如果有这个定义的话，就会新增两个字段：uint64* pintr0 和 uint64* pintr1，后面会使用READ_TIMESTAMP方法把时间戳存进去，很显然这也是一个profile相关的字段，可以在python虚拟机内核层面打上函数运行的时间戳。

### 小结

根据上面可视化工具的使用和源码的阅读，关于python运行函数的方式也变得清晰：

1. 首先在定义函数的时候，python会将函数的代码（包含默认参数、文档等信息）封装成一个PyFunctionObject
2. 调用函数的时候，找到对应的PyFunctionObject，并且从栈中取出对应的参数，递归调用包含那个巨大for loop的主函数，生成一个新的方法帧进行运算
3. 运行函数之后会得到一个返回结果，再把这个结果放入栈中，等待下一步操作

## 预告

这一章节到这里就结束啦，有兴趣的话可以继续阅读下一章：**python中最常见的对象——PyObject**。