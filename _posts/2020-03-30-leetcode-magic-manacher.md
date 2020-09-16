---
layout:     post
title:      "Leectode Magic - Manacher"
subtitle:   "算法笔记：专门用于回文字符串的算法"
date:       2020-03-30 12:00:00
author:     "Baymax"
header-img: "img/post-bg-agt-6.jpg"
catalog: true
tags:
    - Algorithm
    - Leetcode
---

## Manacher算法

最近在Leetcode接连刷到了好几次关于回文字符串的问题，一般来说回文串问题都可以通过暴力来解决（当然其实所有问题都可以暴力），但是时间复杂度太高了，因此捡起了Manacher算法。

### 算法要点

其实Mancher是一种专用于回文串的算法， 讲解相对复杂，但是要点比较简单：

1. 时间和空间复杂度为$O(n)$
2. 作用是查找某一个字符串内所有的回文子串

关于这个算法的讲解网上有很多，就不在多赘述了，这里贴两个讲的比较好的：

> [Manacher - OI Wiki](https://oi-wiki.org/string/manacher/)  
> [Manacher 算法 - 《小窗幽记》语录](https://ethsonliu.com/2018/04/manacher.html)

需要知道的内容是，如果遇到处理回文字符串且对时间复杂度有要求的，想到它再去找代码就可以了。另外一个技巧是处理回文字符串的时候，经常要考虑中间是字符还是空格，在每个字符中间插入'#'这样的特殊字符可以避免这个麻烦。


## Leetcode题目

### [最长回文串](https://leetcode-cn.com/problems/longest-palindromic-substring/)

> 给定一个字符串 s，找到 s 中最长的回文子串。你可以假设 s 的最大长度为 1000。

```python
class Solution:
    def longestPalindrome(self, s: str) -> str:
        string = '$#{}#^'.format('#'.join(x for x in s))
        longest, mx, dp = 0, 0, [1] * len(string)
        for i in range(1, len(string) - 1):
            dp[i] = min(dp[2 * mx - i], mx + dp[mx] - i) if i < mx else 1
            while string[i - dp[i]] == string[i + dp[i]]:
                dp[i] += 1
            if i + dp[i] > mx + dp[mx]:
                mx = i
            if dp[i] > dp[longest]:
                longest = i
        start = (longest - dp[longest] + 1) // 2
        return s[start:start + dp[longest] - 1]
```

这个就是标准的Manacher算法，找到最长的之后再输出即可。

### [最短回文串](https://leetcode-cn.com/problems/shortest-palindrome/)

> 给定一个字符串 s，你可以通过在字符串前面添加字符将其转换为回文串。找到并返回可以用这种方式转换的最短回文串。

```python
class Solution:
    def shortestPalindrome(self, s: str) -> str:
        string = '$#{}#^'.format('#'.join(x for x in s))
        start, mx, dp = 0, 0, [1] * len(string)
        count = 0
        for i in range(1, len(string) - 1):
            dp[i] = min(dp[mx * 2 - i], mx + dp[mx] - i) if mx + dp[mx] > i else 1
            while string[i + dp[i]] == string[i - dp[i]]:
                dp[i] += 1
                count += 1
            if i + dp[i] > mx + dp[mx]:
                mx = i
            if dp[i] == i:
                start = max(start, dp[i] - 1)
        return s[:start - 1:-1] + s
```

加了一点小的变化，实际上是找到以$S[0]$开头的最长回文，再把后面的字符串反向拼接即可。同时也可以使用KMP来做，官方题解也是提供了KMP的算法。

### [回文子串](https://leetcode-cn.com/problems/palindromic-substrings/)

> 给定一个字符串，你的任务是计算这个字符串中有多少个回文子串。
> 具有不同开始位置或结束位置的子串，即使是由相同的字符组成，也会被视作不同的子串。

```python
class Solution:
    def countSubstrings(self, s: str) -> int:
        string = '$#{}#^'.format('#'.join(x for x in s))
        total, mx, dp = 0, 0, [1] * len(string)
        for i in range(1, len(string) - 1):
            dp[i] = min(dp[2 * mx - i], mx + dp[mx] - i) if i < mx else 1
            while string[i - dp[i]] == string[i + dp[i]]:
                dp[i] += 1
            if i + dp[i] > mx + dp[mx]:
                mx = i
            total += dp[i] // 2
        return total
```

这里也加了一点变化，其实如果找到了每个位置开始最长的回文串，那么以它为中心的回文串数量就和长度一致了，这个还是比较好想的。