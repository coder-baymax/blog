---
layout:     post
title:      "我和搜索的那点事儿"
subtitle:   "从最早手撸了一个搜索引擎，到被ES虐的醉生梦死"
date:       2020-06-14 12:00:00
author:     "Baymax"
header-img: "img/post-bg-agt-1.jpg"
catalog: true
tags:
    - Algorithm
    - Project
---

> 老板说了，想要知道我们新闻库里这些新闻有没有，明天能给个demo吗

## 搜索引擎的最小可用版本

第一次遇到这个项目是在2015年，那个时候[ElsaticSearch](https://zh.wikipedia.org/wiki/Elasticsearch)还不流行，大家熟知的搜索系统还是[Lucene](https://zh.wikipedia.org/wiki/Lucene)，需要大量的额外工作量才能真正建立一个搜索引擎。由于当时的需求比较简单，没有很多时间开发，因此直接选择了自己实现一个简单搜索引擎的方案。

今天回想起了当时这个项目，依旧会觉得非常有意思，正好趁这个机会再巩固一下搜索引擎的基本原理，顺带记录一下在ES中遇到的一些坑。

## 基本原理

首先我们要对搜索需求进行抽象，最简单的搜索引擎其实只有两个功能（当然了，除了功能本身以外，我们还需要快速和准确的找到想要的结果）：

- 类似一个数据库，可以插入或者删除某一条内容
- 利用某些关键词，可以命中数据库中的数据并返回结果

看到这个需求首先会想到的是[哈希表(Hash Table)](https://zh.wikipedia.org/zh-hans/%E5%93%88%E5%B8%8C%E8%A1%A8)，这种数据结构在大部分语言里都有极其重要的作用：像Java里面的HashMap、Python的dict等。但是仅使用哈希表只能解决搜索一个长string的问题，不能解决我们搜索关键词的目标，因此还需要一点点小小的魔法。

先把问题简化，假设我们使用英语，并且所有的关键词都由空格切分，用户不会搜索同义词也不会有拼写错误。那么我们只需要把句子变成单词，然后保存一个单词为key，对应的数据id为value的映射，这样我们就可以直接根据关键词找到内容了。

是的，到这一步的话我们已经接近想要的目标了。

### 倒排索引

在Lucene和绝大部分搜索引擎中，使用了[倒排索引](https://zh.wikipedia.org/zh-hans/%E5%80%92%E6%8E%92%E7%B4%A2%E5%BC%95)的数据结构，在搜索引擎相关的书籍里面也会大篇幅介绍这部分内容，但是其本质非常简单，我们用一句代码就可以表述这个东西：

```python
index = {
	key1: set(v1, v2, v3),
	key2: set(v2, v4),
}
```

有了这个数据结构之后，我们如果要查找key1和key2，直接取出两个set做并集操作即可。

### 让数据更准确

我们仅仅找到了命中的结果其实并不能完全满足需求，如何让数据更准确是只要做了搜索，就会一直困扰开发者的话题。

从前面的例子来看，如果用户同时搜索了key1和key2，那么v1-v4都会被命中，虽然结果是对的，但是毫无意义，毕竟我们把所有的内容都返回给了用户。显而易见的是，如果我同时搜索key1和key2，那么我其实最希望看到的结果是v2。

这部分在我的实现里，将使用命中词数量占比作为排序标准，这样就可以保证v2排在其他结果的前面，从而让用户可以第一眼看到想要的结果。

### 针对中文

针对英文的话关键词会非常简单，但是针对中文就不一样了，我们需要一个技术将句子和关键词关联起来。这里就用到了分词技术，分词技术的本质就是将句子拆解为关键词，大部分的分词库原理都非常复杂，因此我们一般会直接使用现有的分词技术。

比较常见的有：

- jieba分词，hanlp分词，这两种提供了第三方库，并且有多种语言支持，在使用的时候基本偏向jieba分词，词库小，速度快
- ik分词，这一项分词器主要是在ES引擎中使用，如果直接使用某些云服务提供的ES，很可能是不支持自定义其他分词器的，就只能用这个了

## Code Time

### 数据结构

例子中仅需要两个数据结构：File和Index。

```python
class File(models.Model):
    context = models.TextField()


class Index(models.Model):
    word = models.CharField(max_length=256, db_index=True)
    file = models.ForeignKey(File, on_delete=models.CASCADE)
```

### 插入方法

创建file之后再批量创建index。

```python
def insert(context):
    words = list(jieba.cut_for_search(context))
    file = File.objects.create(context=context, word_count=len(words))
    links = [Index(word=x, file_id=file.id) for x in words]
    Index.objects.bulk_create(links)
```

### 搜索和排序

搜索直接拉取所有和关键词关联的file，排序使用命中词数量 / 当前文本关键词数量得到score。

```python
def search(keyword):
    words = list(jieba.cut_for_search(keyword))
    file_list = list(File.objects.filter(index__word__in=words))
    counter = Counter([x.id for x in file_list])
    rank = lambda x: counter[x.id] / x.word_count
    return sorted(list(set(file_list)), key=rank, reverse=True)
```

### 测试代码

运行测试代码我们可以看到最相关的句子被命中，并且排到了最前面。

```python
class EngineTest(TestCase):

    def test_insert_search(self):
        insert("黄鑫河是大白的傻儿子")
        insert("黄鑫河想去动物园")
        insert("大白带着傻儿子去逛动物园")
        for file in search("傻儿子逛动物园"):
            print(file.context)
```

## 踩过ES的坑

### 分组聚合坑

这个坑可能很多用ES的小伙伴都会遇到，我们是在这样的场景里面遇到的：

> 已有每个商品日度的销量，聚合得到品牌的月度销量排行榜

我们发现在这个场景下使用ES直接取结果和用Spark预处理以后的数据有着不小的偏差，翻阅了资料以后发现ES的文档里面写的很清楚，明明白白写了聚合的结果就是有可能会不精准的：

> [Document counts are approximate](https://www.elastic.co/guide/en/elasticsearch/reference/current/search-aggregations-bucket-terms-aggregation.html#search-aggregations-bucket-terms-aggregation-approximate-counts)

简单翻译一下，聚合是这样的流程：

- 每一个shard内部进行聚合，并返回share_size数量的结果
- 再根据每个shard的结果进行二次聚合，得到最终的结果

这里就有一个坑了，比如数据被随机分到了3个shard上，这个时候每个shard里面销量的top10汇总并不等于整体的销量top10，ES做了这样的调整是在返回时间上做了妥协，用精确性换了时间。

我们最后找了很多资料，最后根据需求不同，解决方案有两个：

1. 调大shard_size到一定值，提高精确性。
	- 不过这一步是治标不治本的，就是我们每个shard取top30，最后聚合top10，依旧是不精确的
	- 另外shard_size不能太大，否则会导致集群性能急剧下降
2. 把需要精确求值的结果用spark洗好
	- 这个方案主要是会增加数据清洗和存储的成本
	- 同时如果需求变更，那么需要重写代码并重跑脚本

### score计算坑

socre就是关键词和文章的匹配程度，我们例子中使用的是命中词数量/文章词总数，在ES中，计算score的方式就复杂多了，可以看具体的介绍：

> [相关度评分背后的理论](https://www.elastic.co/guide/cn/elasticsearch/guide/current/scoring-theory.html)

在默认情况下，所有ES的命中结果都是根据score来排序的，我们的项目在做结果排序的时候，使用了品牌权重作为一级，score作为二级的排序方式。另外在做分页的时候，我们传入上一页最后一个结果，使用search_after来分页。

但是，前端会反馈说偶尔会有数据重复，他必须手动过滤。经过仔细检查后我们发现，在前后两个请求里，同一条内容的score是有可能不同的！

文档里说明了在score计算的时候，有一步是针对tf/idf进行计算，就需要用到词频，这里就必须得联系上面一个坑[score计算坑](#score计算坑)。这一步和聚合的偏差其实非常类似——每一个shard都会记录自己的词频信息并根据局部词频进行计算，那么再次汇总以后，结果一定会产生偏差。

解决方案是更改search_type为dfs_query_then_fetch：

> [search your data: search_type](https://www.elastic.co/guide/en/elasticsearch/reference/7.8/search-your-data.html#search-type)

但是如果修改search_type之后，整体性能又一落千丈，最后怂了，由于我们是滚动翻页，并不严格要求每次返回的数量，所以后端修改了代码，加上了去重操作。

### ik分词坑

在ES的多词查询中，有多种方式进行匹配选择：
> [multi-match query](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-multi-match-query.html)

从产品角度出发，我们使用了and方式以减少噪音，因此测试的时候遇到了非常多分词问题，主要内容是测试经常会报这个东西搜不到或者那个东西搜不到，一般遇到这个问题，使用analyze来检查分词器：

```bash
POST /_analyze
{
	"analyzer":"ik_smart", 
	"text":"南极人品牌销量"
}
```

由于客户选择使用了阿里云的ES，目前仅支持ik的分词器，ik分词器有两种选择：ik_smart和ik_max_word，在我们尝试了各种组合之后，发现使用ik_max_word进行索引，同时使用ik_smart进行搜索会达到一个比较好的效果。

但是依旧有无法匹配上的情况，前面的南极人品牌就是一个例子，默认会分词成南极、人品、牌，导致用南极人（默认分成南极、人）搜索怎么都无法匹配，解决方案有两个：

- 修改匹配方式为minimum_should_match，设定一个比例
- 将所有的品牌名、行业名、地名等等信息，在数据清洗的时候导出作为词库，导入ES

但是产品为了用户体验能更好，对噪音0容忍，否决了方案1，目前采用的是清洗词库的方案。