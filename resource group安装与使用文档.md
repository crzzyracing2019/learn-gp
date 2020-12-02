
- [一、resource group安装](#一resource-group安装)
  - [1.1. os安装cgroup组件](#11-os安装cgroup组件)
  - [1.2. 编辑cgroup配置文件](#12-编辑cgroup配置文件)
  - [1.3. 查看mount point](#13-查看mount-point)
  - [1.4. 操作系统配置cgroup开机启动](#14-操作系统配置cgroup开机启动)
  - [1.5. 开启resource group](#15-开启resource-group)
  - [1.6. 重启数据库](#16-重启数据库)
- [二、resource group 参数详解](#二resource-group-参数详解)
  - [1. CPU限制](#1-cpu限制)
    - [方式一：按照核数来分配](#方式一按照核数来分配)
    - [方式二：按照百分比来分配](#方式二按照百分比来分配)
  - [2. 内存限制](#2-内存限制)
  - [3. 创建rg并且分配role](#3-创建rg并且分配role)
  - [4. 几个rg相关运维脚本](#4-几个rg相关运维脚本)
- [三、resource queue 与 resource group 区别:](#三resource-queue-与-resource-group-区别)

<br>

# 一、resource group安装
> 官方文档《GPDB611Docs.pdf》p523 Managing Resource   
> resource group（以下简称rg）设计的目的是为了在资源不足的时候**禁止**SQL的执行，而不是协调分发资源；即整体上利用内存、CPU、并发量等指标，通过阻止某些大SQL分得资源来保护绝大多数事务获得资源正常运行。   
> 当执行SQL时，gp先查询当前组是否达超过最大限制，如果没有则立即执行，如果有则进入等待队列（FCFS先到先得）。
如果资源组设置的足够大，gp甚至能执行挂起的SQL。   
> 注意：红帽6版本因为有严重的系统bug不能在开启cgroup的情况下使用gp，`cat /etc/redhat-release`

## 1.1. os安装cgroup组件
> 注意: gp集群中每个节点都要做相同操作, 如果操作系统已经开启则这一步略过

```shell
--centos7
sudo yum install libcgroup-tools
sudo cgconfigparser -l /etc/cgconfig.d/gpdb.conf

--centos6
sudo yum install libcgroup
sudo service cgconfig start
```

## 1.2. 编辑cgroup配置文件
```shell
sudo vi /etc/cgconfig.d/gpdb.conf
```
粘贴下面代码
```shell
group gpdb {
    perm {
    task {
        uid = gpadmin;
        gid = gpadmin;
    }
    admin {
        uid = gpadmin;
        gid = gpadmin;
    }
    }
    cpu {
    }
    cpuacct {
    }
    cpuset {
    }
    memory {
    }
}
```

## 1.3. 查看mount point
```shell
grep cgroup /proc/mounts
```
显示结果中记住第一行的路径,替换下面 cgroup_mount_point
```shell
ls -l <cgroup_mount_point>/cpu/gpdb
ls -l <cgroup_mount_point>/cpuacct/gpdb
ls -l <cgroup_mount_point>/cpuset/gpdb
ls -l <cgroup_mount_point>/memory/gpdb
```
> **如果所有文件都存在，且文件所有者是gpadmin/gpadmin则成功，继续下一步**

## 1.4. 操作系统配置cgroup开机启动
```shell
sudo systemctl enable cgconfig.service
sudo systemctl start cgconfig.service
```

## 1.5. 开启resource group
从此开始只在主节点执行
```shell
gpconfig -s gp_resource_manager
gpconfig -c gp_resource_manager -v "group"
```

## 1.6. 重启数据库
```shell
gpstop
gpstart
```
至此resource group安装成功！

<br>

# 二、resource group 参数详解
## 1. CPU限制
> 可以用CPU核心数方式也按照百分比来分配，但是同一资源组不能两种方式共用
> 参数：gp_resource_group_cpu_limit 即每个segments段主机上的CPU使用最大值，**默认0.9**，剩余CPU用来OS内核和GP辅助进程，所以**不建议超过90%**


### 方式一：按照核数来分配
- 参数：CPUSET = "1,3-4" 即指定1,3,4号CPU专门为资源组服务；此时CPU_RATE_LIMIT = -1
- rg只会使用自己专用的CPU！
- **专用分配方式优先级要高于百分比方式**，即百分比分配的CPU是扣除专用CPU之后剩下的，所以说**尽量少使用专用方式**
- 标号尽量从最小的“1”开始用，避免restore时候报错
- 目前用gpcc创建资源组时不支持这种分配方式

### 方式二：按照百分比来分配
- 参数：CPU_RATE_LIMIT
- 取值1~100，所有rg相加不能超过100；此时CPUSET = -1
- CPU_RATE_LIMIT的最大值 = min(gp_resource_group_cpu_limit,非专用CPU数 / 所有CPU核数 × 100)
> rg对于CPU资源的分配是相对弹性的，它会把闲的CPU分配给忙的rg，但是如果所有rg都处于忙的状态，此时CPU资源的分配就会参考rg设置中的CPU_RATE_LIMIT参数了。

## 2. 内存限制
- 参数：gp_resource_group_memory_limit 为每个点上的内存最大百分比，**默认0.7**
- 每个段主机的内存在gp_resource_group_memory_limit的基础上**平均**分配   
`rg_perseg_mem = ((RAM * (vm.overcommit_ratio%) + SWAP) * gp_resource_group_memory_limit) / num_active_primary_segments`
- 参数：overcommit_ratio 为一次申请的内存不允许超过可用内存的大小
- 参数：MEMORY_LIMIT
  - 取值0~100，创建rg时为必录项
  - =0时，没有预留固定内存, 直接到全局共享区取内存
  - default_group初始值是0, admin_groupp初始值是10
  - 所有rg的MEMORY_LIMIT相加 ≤ 100，建议值 80~90
  - 当 事务没有可用的rg共享内存 and 没有可用的全局共享内存 and 申请额外的内存时，事务将失败！
- 参数：MEMORY_SHARED_QUOTA
  - 取值0~100，指的是共享部分的百分比，**默认80**，即只有20%的分配内存为固定的
  - 对于rg已经分得的内存(MEMORY_LIMIT>0 and sum(MMEORY_LIMIT)<=100),再分为固定部分和共享部分
- 参数：MEMORY_SPILL_RATIO
  - 取值0~100，默认值是0，就是没有阈值，=0时gp使用statement_mem参数来分配事务的初始内存
  - 一个事务里内存敏感型操作的阈值，如果达到阈值则数据由内存向磁盘spill
  - gp用这个参数来确定对事务的初始内存分配
  - 若rg里MEMORY_LIMIT = 0，则memory_spill_ratio也必须是0
  - 当 memory_spill_ratio <= 2 且 statement_mem <= 10M 时，**对内存需求较低的事务**会有较高的效率，可以在事务级进行控制:
    ```sql
    SET memory_spill_ratio=0;
    SET statement_mem='10 MB';
    ```
- 全局共享内存：
  - 当所有rg的MEMORY_LIMIT之和 < 100时，全局共享内存被启用，剩余内存被收集形成shared pool
  - 当全局共享内存 = 100 - sum(MEMORY_LIMIT) 介于10~20%时，gp会更有效的使用rg分配内存！
  - 分配算法采用先到先得FCFS
  - 全局共享内存的使用还有助于缓解内存消耗或不可预测的查询失败
    

**综上：**   
(1) 每个host的可用内存 = RAM × gp_resource_group_memory_limit%   
(2) 每个segment的可用内存 = 每个host的可用内存 / 主segments数量   
(3) 每个rg的内存 = 每个segment的内存 × MEMORY_LIMIT%   
(4) 其中共享部分 = 每个rg的内存 × MEMORY_SHARED_QUOTA%   
(5) 其中固定部分 = 每个rg的内存 × (100 - MEMORY_SHARED_QUOTA)%   
(6) 事务槽 = 其中固定部分 / rg的并发数   
(7) 全局共享内存 = 每个segment的可用内存 × (100 - sum(MEMORY_LIMIT))%    

**内存使用优先级：当前事务槽(6) ==> rg中共享部分(4) ==> 全局共享内存(7) ==> 事务失败**

![](png/png_rg_resgroupmem.png)

## 3. 创建rg并且分配role
```sql
--创建rg
=# CREATE RESOURCE GROUP rgroup1 WITH (CPU_RATE_LIMIT=20, MEMORY_LIMIT=25);
=# ALTER RESOURCE GROUP rg_role_light SET CONCURRENCY 7;

--删除rg
=# DROP RESOURCE GROUP exec; 

--为role分配rg
=# ALTER ROLE bill RESOURCE GROUP rg_light;
=# CREATE ROLE mary RESOURCE GROUP exec;

--从资源组中删除role
=# ALTER ROLE mary RESOURCE GROUP NONE;
```

## 4. 几个rg相关运维脚本

```sql
--查看rg配置
SELECT * FROM gp_toolkit.gp_resgroup_config;

--查看rg实时状态
SELECT * FROM gp_toolkit.gp_resgroup_status;
SELECT * FROM gp_toolkit.gp_resgroup_status_per_host;
SELECT * FROM gp_toolkit.gp_resgroup_status_per_segment;

--查看用户在哪个rg
SELECT rolname, rsgname FROM pg_roles, pg_resgroup WHERE pg_roles.rolresgroup=pg_resgroup.oid;
```

<br>

# 三、resource queue 与 resource group 区别:

|参数 |   资源队列 |  资源组 |
| --- | --- | --- |
|并行 |   在查询级别管理 |   在事务级别管理
|CPU |  指定队列顺序 |    指定CPU的使用百分比；使用Linux控制组
|内存 |   在队列和操作级别管理；用户可以过量使用 | 在事务级别管理，可以进一步分配和追踪；用户不可以过量使用。
|内存隔离 | 无 |     同资源组下的事务使用的内存是隔离的，不同资源组使用的内存也是隔离的。 |
|用户 |   仅非管理员用户有限制。 | 非管理员用户和超级用户都有限制 |
|排序 |   当没有可用槽位时，才开始排序  | 当槽位或内存不足时，开始排序 |
|查询失效 | 当内存不足时，查询可能会立即失效 | 在没有更多的共享资源组内存的情况下，若事务到达了内存使用量限制后仍然提出增加内存的申请，查询可能会失效  |
|避开限制 | 超级用户以及特定的操作者和功能不受限制。| SET、RESET和SHOW指令不受限制
|外部组件 | 无 | 管理PL/Container CPU和内存资源 |
**resource group（需要安装和启用） 和 resource queue（默认安装）只能二选一** 



![](png/resource_queues.jpg)


内存配额
- SQL提交到server端会被分配一定内存，并且生成一个**执行计划树**，计划树的每个节点都是一个“运算符”，例如排序连接和哈希连接。
每个运算符都是单独执行的线程（至少100KB）
- 默认只会评估SELECT、SELECT INTO、CREATE TABLE AS SELECT和 DECLARE CURSOR声明；如果服务器配置的resource_select_only参数为off，那么INSERT、UPDATE 和DELETE声明也会受评估。

