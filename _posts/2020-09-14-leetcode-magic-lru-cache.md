---
layout:     post
title:      "Leectode Magic - Lru Cache"
subtitle:   "算法笔记：使用函数缓存应对复杂的推导和动态规划"
date:       2020-09-14 12:00:00
author:     "Baymax"
header-img: "img/post-bg-agt-7.jpg"
catalog: true
tags:
    - Algorithm
    - Leetcode
---

## 函数缓存

函数缓存属于一个更大的话题——**记忆化**（[Wiki - Memoization](https://en.wikipedia.org/wiki/Memoization)），其定义是保存一部分运行的结果，增大空间开销从而减少时间开销。

在函数式编程里要求，参数一致的情况下函数返回的结果需要保持一致，因此会非常适合函数缓存。在Python3的官方库里，加入了**lru_cache**的装饰器，让我们可以非常方便的使用函数缓存：

> [Python Doc - functools.lru_cache](https://docs.python.org/3/library/functools.html#functools.lru_cache)

LRU缓存（[Wiki - LRU](https://en.wikipedia.org/wiki/Cache_replacement_policies#Least_recently_used_(LRU))）是一种“最近最少使用”的缓存机制，我们在使用官方装饰器的时候，可以限制缓存的大小，防止缓存使用太多的空间，Leetcode上也有这种缓存的算法题目来练手：[LRU Cache](https://leetcode-cn.com/problems/lru-cache/)。

### 函数缓存和动态规划的关系

我们使用一个斐波那契数列的例子来讨论这个问题，如果我们使用递归来计算，那么很容易写出递归式：$f(n) = f(n-1) + f(n-2)$，但是如果直接使用这个函数来写递归，那么我们会遇到一个巨大的问题：对于 $f(n-2)$ 我们就需要计算2次，对于 $f(n-3)$ 则需要4次，最终导致算法的复杂度为 $O(2^n)$。

我们一般会使用**递推**的方式来解决这个问题，复杂度可以直接降为 $O(n)$。不过函数缓存给了我们一种更快捷直观的选择，我们在函数上直接加入缓存，这样每一个 $f(x)$ 只需要计算一次，下一次就会直接使用缓存，我们同样可以将复杂度降到 $O(n)$，在增长量级上和递推一致。

动态规划也是同理，在写出转移方程之后，直接使用递推写代码往往需要很多的边界条件判断，非常容易出错。另外在某些情况下，可能递推是难以解决问题的，在后面的题目中会看到。

## Leetcode题目

### [不同的子序列](https://leetcode-cn.com/problems/distinct-subsequences/)

> 给定一个字符串 S 和一个字符串 T，计算在 S 的子序列中 T 出现的个数。

> 一个字符串的一个子序列是指，通过删除一些（也可以不删除）字符且不干扰剩余字符相对位置所组成的新字符串。（例如，"ACE" 是 "ABCDE" 的一个子序列，而 "AEC" 不是）

```python
class Solution:
    def numDistinct(self, s: str, t: str) -> int:
        @lru_cache(None)
        def get(i, j):
            if i < 0:
                return 0
            elif j == 0:
                extra = 1 if s[i] == t[j] else 0
                return get(i - 1, j) + extra
            else:
                extra = get(i - 1, j - 1) if s[i] == t[j] else 0
                return get(i - 1, j) + extra

        return get(len(s) - 1, len(t) - 1)
```

这个题目是一个动态规划，直接使用递归和缓存，在保持复杂度的情况下降低了编码成本。

### [扰乱字符串](https://leetcode-cn.com/problems/scramble-string/)

> 给定一个字符串 s1，我们可以把它递归地分割成两个非空子字符串，从而将其表示为二叉树。在扰乱这个字符串的过程中，我们可以挑选任何一个非叶节点，然后交换它的两个子节点。

> 我们将 "rgeat” 称作 "great" 的一个扰乱字符串。给出两个长度相等的字符串 s1 和 s2，判断 s2 是否是 s1 的扰乱字符串。

```python
class Solution:
    def isScramble(self, s1: str, s2: str) -> bool:
        @lru_cache(None)
        def check(i, j, x, y):
            if s1[i:j] == s2[x:y]:
                return True
            for k in range(i + 1, j):
                z1, z2 = k - i + x, j - k + x
                if check(i, k, x, z1) and check(k, j, z1, y) or \
                        check(i, k, z2, y) and check(k, j, x, z2):
                    return True
            return False

        if sorted(s1) != sorted(s2):
            return False
        elif s1 == s2:
            return True
        else:
            return check(0, len(s1), 0, len(s2))
```

我们对任意两个字符串 $s1$ 和 $s2$ 进行检查，有这么几种可能性：

- 如果 $s1==s2$ 那么结果是True
- 将 $s1$ 切割成 $s1_a$ 和 $s1_b$， $s2$ 切割成对应的 $s2_a$ 和 $s2_b$（这里有两种切割方式，在下面的比较中保持两个比较的字符串长度一致），那么：
	- 如果检查 $s1_a$ 与 $s2_a$、$s1_b$ 与 $s2_b$ 结果是True，那么结果是True
	- 如果检查 $s1_a$ 与 $s2_b$、$s1_b$ 与 $s2_a$ 结果是True，那么结果是True
- 如果所有的切割方案检查的结果都是False，那么结果是False

上面这段判断如果写成递推会非常复杂，写成递归的话思路就非常清晰。

### [交错字符串](https://leetcode-cn.com/problems/interleaving-string/)

> 给定三个字符串 s1, s2, s3, 验证 s3 是否是由 s1 和 s2 交错组成的。

```python
class Solution:
    def isInterleave(self, s1: str, s2: str, s3: str) -> bool:
        @lru_cache(None)
        def check(i, j, k):
            if i == -1 and j == -1 and k == -1:
                return True
            if i >= 0 and s1[i] == s3[k] and check(i - 1, j, k - 1):
                return True
            if j >= 0 and s2[j] == s3[k] and check(i, j - 1, k - 1):
                return True
            return False

        if sorted(s1 + s2) != sorted(s3):
            return False
        return check(len(s1) - 1, len(s2) - 1, len(s3) - 1)
```

这个和上面的**扰乱字符串**类似，许多字符串判断问题都可以用类似的解法，不赘述了。

### [快速公交](https://leetcode-cn.com/problems/meChtZ/)

> 小扣打算去秋日市集，由于游客较多，小扣的移动速度受到了人流影响：

> - 小扣从 x 号站点移动至 x + 1 号站点需要花费的时间为 inc；
> - 小扣从 x 号站点移动至 x - 1 号站点需要花费的时间为 dec。

> 现有 m 辆公交车，编号为 0 到 m-1。小扣也可以通过搭乘编号为 i 的公交车，从 x 号站点移动至 jump[i]*x 号站点，耗时仅为 cost[i]。小扣可以搭乘任意编号的公交车且搭乘公交次数不限。

> 假定小扣起始站点记作 0，秋日市集站点记作 target，请返回小扣抵达秋日市集最少需要花费多少时间。由于数字较大，最终答案需要对 1000000007 (1e9 + 7) 取模。

```python
class Solution:
    def busRapidTransit(self, target: int, inc: int, dec: int, jump: List[int], cost: List[int]) -> int:
        @lru_cache(None)
        def search(num):
            if num == 0:
                return 0
            result = num * inc
            for i in range(len(jump)):
                last, left = num // jump[i], num % jump[i]
                result = min(result, search(last) +
                             cost[i] + inc * left)
                if num > 1 and left > 0:
                    result = min(result, search(last + 1) +
                                 cost[i] + dec * (jump[i] - left))
            return result

        return search(target) % 1000000007
```

这道题是Leetcode一次季赛的倒数第二题，题目表述很复杂，有着不小的难度。其实如果按照递归的思路来想就会比较顺利，针对需要到达的目标点 $target$，其实只有三种方案：

1. 直接步行到 $target$
2. 坐一辆车到一个位置 $loc<=target$ ，然后往前走到 $target$
3. 坐一辆车到一个位置 $loc>target$ ，然后往回走到 $target$

在递归的时候，分别计算这几种可能性，并且取最小值即可。有一个要注意的是当 $target==1$ 的时候需要加入额外的边界条件判断，否则会死循环。

这个题目就是前面说到的**不能使用递推**的情况，如果我们按照递推解题，其实是一个最短路径的建模，但是题目给出的范围是 $1 <= target <= 10^9$，使用递推的话中间非常多的节点可能是根本不需要进行计算的，这道题目会直接超时。