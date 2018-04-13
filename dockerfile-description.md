AWS Batch, Amazon ECS を実行するためのサンプルイメージです。

AWS S3 においてあるテキストファイルを読み込み、単語の登場回数をカウントして多い順にソートした結果を AWS S3 に出力します。

**使用方法**

`docker run aokad/aws-wordcount ash run.sh s3://input.txt s3://output.txt`

入力ファイルの例：

Humpty Dumpty sat on a wall,
Humpty Dumpty had a great fall.
All the king's horses and all the king's men
Couldn't put Humpty together again.


出力ファイルの例：

  humpty:    3
       a:    2
     all:    2
  dumpty:    2
   kings:    2
     the:    2
(以下省略)

