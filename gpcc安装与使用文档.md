- [前言](#前言)
  - [gpcc功能点总览](#gpcc功能点总览)
  - [帮助文档](#帮助文档)
- [gpcc安装步骤](#gpcc安装步骤)
  - [0. 安装先决条件](#0-安装先决条件)
  - [1. 下载安装包](#1-下载安装包)
  - [2. 上传安装包](#2-上传安装包)
  - [3. 创建安装路径](#3-创建安装路径)
  - [4. 运行安装程序](#4-运行安装程序)
  - [5. 更新/安装 Metrics Collector Extension](#5-更新安装-metrics-collector-extension)
  - [6. 启动gpcc](#6-启动gpcc)
  - [7. 安装中可能遇到的问题](#7-安装中可能遇到的问题)

# 前言
## gpcc功能点总览
在官方文档GPDB611Docs.pdf 第五章 580页介绍如下:
- 可以直接操作pg_hba.conf
- 4层gpcc用户权限控制
- 从5个地方“拿数”：OS级，DB级，gpperfmon，catalog表，query，workload man
- 使用UDP协议 
- 使用gpsmon进程搜集系统监控信息，每隔15秒，主节点发送指令来搜集
- 由3种表组成：now , history, tail tables
- gpperfmon_install创建gpperfmon database
- 3种情况发起查询统计：1.提交查询 2.查询状态变更 3.查询节点开始，变更，结束
- gp_enable_query_metrics = on 并且重启集群！
- 从表pg_catalog数据库的gp_segment_configuration表中提取segments的列表

## 帮助文档
https://tanzu.vmware.com/support   
https://gpcc.docs.pivotal.io/630/topics/overview.html   

</br>

# gpcc安装步骤
## 0. 安装先决条件
- gp集群必须安装并且正常运行
- 必须设置MASTER_DATA_DIRECTORY环境变量
- gpcc的安装目录（默认/usr/local）在gp所有节点都有gpadmin用户的读写权
- mdw或smdw必须开放端口28080（BS模式的访问端口，可以更改）
- 所有sdwN节点必须开放8899端口（RPC远程调用接口）
- 所有节点必须安装 Apache Portable Runtime Utility library 类库   
  使用 ``` yum install apr-util 或 apt install libapr1 ``` 安装
- （非必须）浏览器免密登录需要配置SSL秘钥

## 1. 下载安装包
下载到官网：https://network.pivotal.io/products/pivotal-gpdb   

![](png/gpcc1.png)

搜索 `command center`
查看os发行版本`cat /etc/redhat-release`，按照对应的os版本下载     
下载前必须要注册用户
选择安装包：greenplum-cc-web-6.3.1-gp6-rhel7-x86_64.zip   

![](png/gpcc2.png)

</br>

## 2. 上传安装包
上传greenplum-cc-web-6.3.1-gp6-rhel7-x86_64.zip 到mdw或smdw服务器中 gpadmin 用户的/home目录下，解压缩
```shell
$ unzip greenplum-cc-web-gp6-<version>-<platform>.zip
```
</br>

## 3. 创建安装路径
> 要求在gp所有节点操作；或者使用gpssh，把hostfile置换成gp的host集群，每个host的ip占一行
```shell
$ source /usr/local/greenplum-db-<version>/greenplum_path.sh
$ gpssh -f <hostfile> 'sudo mkdir -p /usr/local/greenplum-cc-6.3.0'
$ gpssh -f <hostfile> 'sudo chown -R gpadmin:gpadmin /usr/local/greenplum-cc-6.3.0'
$ gpssh -f <hostfile> 'sudo ln -s /usr/local/greenplum-cc-6.3.0 /usr/local/greenplum-cc'
```

</br>

## 4. 运行安装程序
gpcc总共四种安装方式：
- 交互式安装
- 静默安装
- 默认方式安装
- 更新gpcc

运行安装程序：
```shell
$ source /usr/local/greenplum-db/greenplum_path.sh
$ cd greenplum-cc-<version>
$ ./gpccinstall-<version> -W
```

</br>

## 5. 更新/安装 Metrics Collector Extension
> 如果安装的gpcc版本比它支持的gp的版本更高，就需要为gp更新metrics_collector这个扩展功能   
> 必须删除旧的metrics_collector，安装新的metrics_collector，重启gpdb数据库   
> 如果想用新版本的特性则必须安装新的metrics_collector，如果不想用新特性，可以使用旧的metrics_collector   

- 直接运行MetricsCollector中的安装脚本即可！脚本都是解压好的
- 创建用户 gpmon   
需要创建超级用户gpmon ， 如果原来没有，那么gpcc安装过程中会自动创建这个用户，
但是密码需要新输入一遍，安装过程会有提示使用 -W 参数，首次输入一定要记住密码！

</br>

## 6. 启动gpcc
```shell
安装完成重启gp:
$ gpstop -a , gpstart -a

启动gpcc： 
$ gpcc start -W
```

**gpcc登录地址：http://[master_ip or standby_master_ip]:28080/login**

</br>

## 7. 安装中可能遇到的问题
- 安装前gpmon用户没有提前创建：
  - 解决方法：
    - 使用默认安装方式(-auto)会自动创建gpmon用户，但是需要指定密码
    - 用这种方式安装的时候需要使用 -W 参数输入密码
    - 如果gpsmon已经创建不要建-W密码
- gpmon 和 gpadmin 用户不能登录到gpcc
  - 原因：gpmon 和 gpadmin 两个用户属于superuser，superuser创建时默认的登录方式都是trust
  - 解决方法：
    - 修改 pg_hda.conf ，把gpmon用户所有的trust方式改成md5
    - 使配置文件生效：gpstop -u 
    - 重启gpcc： gpcc start -W

![](png/gpcc3.png)


