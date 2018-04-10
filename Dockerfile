FROM python:3.6.5-alpine3.7

MAINTAINER aokad <aokad@hgc.jp>

RUN pip install awscli && \
    wget https://raw.githubusercontent.com/aokad/ecsub/master/examples/wordcount.py && \
    \
    echo "set -x"                                                         > /run.sh && \
    echo "aws s3 cp \$1 ./input"                                         >> /run.sh && \
    echo "python wordcount.py ./input ./output"                          >> /run.sh && \
    echo "aws s3 cp ./output \$2"                                        >> /run.sh && \
    \
    chmod 744 /run.sh
    
CMD ["/run.sh"]
