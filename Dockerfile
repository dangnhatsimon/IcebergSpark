FROM python:3.12.9-bullseye AS spark-base

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      sudo \
      curl \
      vim \
      unzip \
      rsync \
      openjdk-17-jdk \
      build-essential \
      software-properties-common \
      ssh && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

## Download spark and hadoop dependencies and install

# ENV variables
ENV SPARK_VERSION=4.0.0
ENV SCALA_VERSION=2.13
ENV ICEBERG_VERSION=1.9.0

ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV SPARK_HOME=${SPARK_HOME:-"/opt/spark"}
ENV HADOOP_HOME=${HADOOP_HOME:-"/opt/hadoop"}

ENV SPARK_MASTER_PORT=7077
ENV SPARK_MASTER_HOST=delta-streaming-spark-master
ENV SPARK_MASTER="spark://$SPARK_MASTER_HOST:$SPARK_MASTER_PORT"

ENV PYTHONPATH=$SPARK_HOME/python/:$PYTHONPATH
ENV PYSPARK_PYTHON=python3

# Add iceberg spark runtime jar to IJava classpath
ENV IJAVA_CLASSPATH=/opt/spark/jars/*

RUN mkdir -p ${HADOOP_HOME} && mkdir -p ${SPARK_HOME}
WORKDIR ${SPARK_HOME}

# Download spark
# see resources: https://dlcdn.apache.org/spark/spark-3.5.5/
# filename: spark-3.5.5-bin-hadoop3.tgz
RUN mkdir -p ${SPARK_HOME} \
    && curl https://dlcdn.apache.org/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop3-connect.tgz -o spark-${SPARK_VERSION}-bin-hadoop3-connect.tgz \
    && tar xvzf spark-${SPARK_VERSION}-bin-hadoop3-connect.tgz --directory ${SPARK_HOME} --strip-components 1 \
    && rm -rf spark-${SPARK_VERSION}-bin-hadoop3-connect.tgz

# Add spark binaries to shell and enable execution
RUN chmod u+x /opt/spark/sbin/* && \
    chmod u+x /opt/spark/bin/*
ENV PATH="$PATH:$SPARK_HOME/bin:$SPARK_HOME/sbin"

# Add a spark config for all nodes
COPY spark-config/* "$SPARK_HOME/conf/"


FROM spark-base AS pyspark

# Install python deps
COPY requirements.txt .
RUN pip3 install -r requirements.txt


FROM pyspark AS pyspark-runner

## Download iceberg spark runtime
RUN curl https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark-runtime-3.5_2.13/${ICEBERG_VERSION}/iceberg-spark-runtime-3.5_2.13-${ICEBERG_VERSION}.jar -Lo /opt/spark/jars/iceberg-spark-runtime-3.5_2.13-${ICEBERG_VERSION}.jar

# Download Nessie Spark Extension
RUN curl https://repo1.maven.org/maven2/org/projectnessie/nessie-integrations/nessie-spark-extensions-3.5_2.13/0.104.1/nessie-spark-extensions-3.5_2.13-0.104.1.jar -Lo /opt/spark/jars/nessie-spark-extensions-3.5_2.13-0.104.1.jar

# Download delta jars
#RUN curl https://repo1.maven.org/maven2/io/delta/delta-spark_2.13/3.3.2/delta-spark_2.13-3.3.2.jar -Lo /opt/spark/jars/delta-spark_2.13-3.3.2.jar \
#    && curl https://repo1.maven.org/maven2/io/delta/delta-core_2.13/2.4.0/delta-core_2.13-2.4.0.jar -Lo /opt/spark/jars/delta-core_2.13-2.4.0.jar \
#    && curl https://repo1.maven.org/maven2/io/delta/delta-storage/3.3.2/delta-storage-3.3.1.jar -Lo /opt/spark/jars/delta-storage-3.3.2.jar

## Download hudi jars
#RUN curl https://repo1.maven.org/maven2/org/apache/hudi/hudi-spark3-bundle_2.12/0.15.0/hudi-spark3-bundle_2.12-0.15.0.jar -Lo /opt/spark/jars/hudi-spark3-bundle_2.12-0.15.0.jar

## Download hive and derby jars
#RUN curl https://repo1.maven.org/maven2/org/apache/derby/derby/10.17.1.0/derby-10.17.1.0.jar -Lo /opt/spark/jars/derby-10.17.1.0.jar \
#    && curl https://repo1.maven.org/maven2/org/apache/hive/hive-exec/4.0.1/hive-exec-4.0.1.jar -Lo /opt/spark/jars/hive-exec-4.0.1.jar \
#    && curl https://repo1.maven.org/maven2/org/apache/hive/hive-metastore/4.0.1/hive-metastore-4.0.1.jar -Lo /opt/spark/jars/hive-metastore-4.0.1.jar

# Download S3 jars
RUN curl https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/3.3.4/hadoop-aws-3.3.4.jar -Lo /opt/spark/jars/hadoop-aws-3.3.4.jar \
    && curl https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/1.12.782/aws-java-sdk-bundle-1.12.782.jar -Lo /opt/spark/jars/aws-java-sdk-bundle-1.12.782.jar \
    && curl https://repo1.maven.org/maven2/software/amazon/awssdk/bundle/2.31.59/bundle-2.31.59.jar -Lo /opt/spark/jars/bundle-2.31.59.jar \
    && curl https://repo1.maven.org/maven2/software/amazon/awssdk/url-connection-client/2.31.59/url-connection-client-2.31.59.jar -Lo /opt/spark/jars/url-connection-client-2.31.59.jar

# Download AWS bundle
RUN curl -s https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-aws-bundle/${ICEBERG_VERSION}/iceberg-aws-bundle-${ICEBERG_VERSION}.jar -Lo /opt/spark/jars/iceberg-aws-bundle-${ICEBERG_VERSION}.jar

## Download GCP bundle
#RUN curl -s https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-gcp-bundle/${ICEBERG_VERSION}/iceberg-gcp-bundle-${ICEBERG_VERSION}.jar -Lo /opt/spark/jars/iceberg-gcp-bundle-${ICEBERG_VERSION}.jar
#
## Download Azure bundle
#RUN curl -s https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-azure-bundle/${ICEBERG_VERSION}/iceberg-azure-bundle-${ICEBERG_VERSION}.jar -Lo /opt/spark/jars/iceberg-azure-bundle-${ICEBERG_VERSION}.jar

# Install AWS CLI
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && sudo ./aws/install \
    && rm awscliv2.zip \
    && rm -rf aws/ \


# Download Structure Streaming Spark jars
RUN curl https://repo1.maven.org/maven2/org/apache/spark/spark-sql-kafka-0-10_2.13/4.0.0/spark-sql-kafka-0-10_2.13-4.0.0.jar -Lo /opt/spark/jars/spark-sql-kafka-0-10_2.13-4.0.0.jar \
    && curl https://repo1.maven.org/maven2/org/apache/spark/spark-sql_2.13/4.0.0/spark-sql_2.13-4.0.0.jar -Lo /opt/spark/jars/spark-sql_2.13-4.0.0.jar

# Download metadata platform OpenLineage jars
RUN curl https://repo1.maven.org/maven2/io/openlineage/openlineage-spark_2.13/1.33.0/openlineage-spark_2.13-1.33.0.jar -Lo /opt/spark/jars/openlineage-spark_2.13-1.33.0.jar

## Add a notebook command
#RUN echo '#! /bin/sh' >> /bin/notebook \
#    && echo 'export PYSPARK_DRIVER_PYTHON=jupyter-notebook' >> /bin/notebook \
#    && echo "export PYSPARK_DRIVER_PYTHON_OPTS=\"--notebook-dir=/home/iceberg/notebooks --ip='*' --NotebookApp.token='' --NotebookApp.password='' --port=8888 --no-browser --allow-root\"" >> /bin/notebook \
#    && echo "pyspark" >> /bin/notebook \
#    && chmod u+x /bin/notebook
#
## Add a pyspark-notebook command (alias for notebook command for backwards-compatibility)
#RUN echo '#! /bin/sh' >> /bin/pyspark-notebook \
#    && echo 'export PYSPARK_DRIVER_PYTHON=jupyter-notebook' >> /bin/pyspark-notebook \
#    && echo "export PYSPARK_DRIVER_PYTHON_OPTS=\"--notebook-dir=/home/iceberg/notebooks --ip='*' --NotebookApp.token='' --NotebookApp.password='' --port=8888 --no-browser --allow-root\"" >> /bin/pyspark-notebook \
#    && echo "pyspark" >> /bin/pyspark-notebook \
#    && chmod u+x /bin/pyspark-notebook
#
#RUN mkdir -p /root/.ipython/profile_default/startup
#COPY ipython/startup/00-prettytables.py /root/.ipython/profile_default/startup
#COPY ipython/startup/README /root/.ipython/profile_default/startup


COPY .pyiceberg.yaml /root/.pyiceberg.yaml

COPY entrypoint.sh .
RUN chmod u+x /opt/spark/entrypoint.sh


# Optionally install Jupyter
FROM pyspark-runner AS pyspark-jupyter

RUN pip3 install notebook

ENV JUPYTER_PORT=8889

ENV PYSPARK_DRIVER_PYTHON=jupyter
ENV PYSPARK_DRIVER_PYTHON_OPTS="notebook --no-browser --allow-root --ip=0.0.0.0 --port=${JUPYTER_PORT}"
 # --ip=0.0.0.0 - listen all interfaces
 # --port=${JUPYTER_PORT} - listen ip on port 8889
 # --allow-root - to run Jupyter in this container by root user. It is adviced to change the user to non-root.


ENTRYPOINT ["./entrypoint.sh"]
CMD [ "bash" ]

# Now go to interactive shell mode
# -$ docker exec -it spark-master /bin/bash
# then execute
# -$ pyspark

# If Jupyter is installed, you will see an URL: `http://127.0.0.1:8889/?token=...`
# This will open Jupyter web UI in your host machine browser.
# Then go to /warehouse/ and test the installation.