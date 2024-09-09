#!/bin/bash

# Variáveis
S3_BUCKET_NAME="treinamentoiteris"
CLOUDFRONT_DISTRIBUTION_ID_FILE="cloudfront_distribution_id.txt"
INDEX_FILE="index.html"
INDEX_FILE_PATH="./$INDEX_FILE" # Ajuste o caminho conforme necessário

# 1. Provisionar o bucket S3
echo "Criando o bucket S3..."
aws s3api create-bucket --bucket $S3_BUCKET_NAME --region us-east-1 --create-bucket-configuration LocationConstraint=us-east-1
if [ $? -ne 0 ]; then
  echo "Erro ao criar o bucket S3. O bucket pode já existir."
  exit 1
fi

echo "Bucket S3 criado com sucesso: $S3_BUCKET_NAME"

# 2. Carregar o conteúdo estático no bucket S3
echo "Carregando o conteúdo estático no bucket S3..."
aws s3 cp $INDEX_FILE_PATH s3://$S3_BUCKET_NAME/
if [ $? -ne 0 ]; then
  echo "Erro ao carregar o conteúdo no bucket S3."
  exit 1
fi

echo "Conteúdo carregado com sucesso no bucket S3."

# 3. Configurar a distribuição CloudFront
echo "Criando a distribuição CloudFront..."
DISTRIBUTION_ID=$(aws cloudfront create-distribution \
  --origin-domain-name "$S3_BUCKET_NAME.s3.amazonaws.com" \
  --default-root-object "index.html" \
  --query 'Distribution.Id' \
  --output text)
if [ $? -ne 0 ]; then
  echo "Erro ao criar a distribuição CloudFront."
  exit 1
fi

echo "Distribuição CloudFront criada com sucesso. ID: $DISTRIBUTION_ID"
echo $DISTRIBUTION_ID > $CLOUDFRONT_DISTRIBUTION_ID_FILE
