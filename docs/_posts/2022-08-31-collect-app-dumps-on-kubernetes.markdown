---
layout: post
title:  "Collect app dumps on kubernetes"
date:   2022-08-31 15:03:27 +0800
categories: DevOps
tags: Debug DevOps Kubernetes
---

# Background
当容器中的应用崩溃时，会使容器发出SIGKILL信号，之后容器会立刻崩溃，
导致程序的dump文件也被一起销毁。为了能够保存dump文件，以便之后调查
分析程序崩溃的原因，所以需要一种机制能够收集并保存dump文件。

# 原理
1. 使用hostPath类型的volume挂载到应用的dump输出路径上，对于java程序，
通常在程序启动时可以通过 -XX:HeapDumpPath=$HEAP_DUMP_PATH 来指定dump path，这样就能够将dump文件保存到node所在的磁盘上；
2. 运行DaemonSet，监控node上保存应用dump的目录，检测到目录CREATE/MODIFY等Event时，将dump目录同步到dumps文件服务器；

# 设计方案
## 应用pod挂载HostPath volume到dump path
```java
// Program will crash if JVM's maximum memory is less than 12MB
public class HelloWorld {
   static final int SIZE=2*1024*1024; // 8MB
    public static void main(String []args) {
      try {
         System.out.println("Hello World");
         Thread.sleep(30*1000);

         int[] i = new int[SIZE];
      } catch(Exception e) {
         e.printStackTrace(); 
      }
    }
}
```

```shell
# run.sh
 java -Xmx12m -XX:+HeapDumpOnOutOfMemoryError -XX:+PrintGCApplicationStoppedTime -XX:HeapDumpPath=dumps/target -jar HelloWorld.jar
```

```yaml
spec:
  containers:
    - image: rhzx3519/ubuntu:dumps
      name: ubuntu
      volumeMounts:
        - name: vardumps
          mountPath: /app/dumps # 挂载到app dump path
  volumes:
    - name: vardumps
      hostPath:
        path: /var/opt/dumps  # node dumps目录
```

## 监控pod
```shell
# monitor.sh

inotifywait -mrq --format '%e' --event create,delete,modify  $filename | while read event
do
  case $event in MODIFY|CREATE|DELETE) bash $script ;;
  esac
done
```

```shell
# upload.sh

function main() {
    (cd $dumpsDir && clear) # 递归地清理dump文件

    upload # 上传dump文件 host
}
```

## 文件服务器

文件服务器使用nginx实现
```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: file-server
  name: file-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: file-server
  template:
    metadata:
      labels:
        app: file-server
    spec:
      containers:
        - image: nginx:stable
          name: file-server
          volumeMounts:
            - mountPath: /etc/nginx/conf.d
              name: config
              readOnly: true
            - mountPath: /data/repo
              name: file-storage
          ports:
            - containerPort: 80
              protocol: TCP
              name: http
            - containerPort: 22
              protocol: TCP
              name: ftp
      volumes:
        - name: file-storage
          emptyDir: {}
        - name: config
          configMap:
            name: nginx-conf-configmap
---
# nginx
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-conf-configmap
data:
  nginx.conf: |-
    server {
        listen 80;
        listen  [::]:80;
        server_name  localhost;

        charset utf-8;

        # download
        autoindex on;               # enable directory listing output
        autoindex_exact_size off;   # output file sizes rounded to kilobytes, megabytes, and gigabytes
        autoindex_localtime on;     # output local times in the directory
        autoindex_format html;      # 以html风格将目录展示在浏览器中

        location / {
            root /data/repo/;
        }
    }
```


# 引用
1. [Handling Core-Dumps in Kubernetes Clusters in GCP](https://faun.pub/handling-core-dumps-in-kubernetes-clusters-in-gcp-b1b2a54c25dc)
2. [GitHub dumps](https://github.com/Devops-in-Wollongong/dumps)
