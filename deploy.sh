#!/bin/bash

# Variáveis
S3_BUCKET_NAME="treinamentoiteris"
CLOUDFRONT_DISTRIBUTION_ID_FILE="cloudfront_distribution_id.txt"
INDEX_FILE="index.html"
OAI_COMMENT="OAI para acesso ao bucket S3"
OAI_ID_FILE="cloudfront_oai_id.txt"

# 1. Provisionar o bucket S3
echo "Criando o bucket S3..."
aws s3api create-bucket --bucket $S3_BUCKET_NAME --region us-east-1
if [ $? -ne 0 ]; then
  echo "Erro ao criar o bucket S3."
  exit 1
fi

echo "Bucket S3 criado com sucesso: $S3_BUCKET_NAME"

# 2. Carregar o conteúdo estático no bucket S3
echo "Carregando o conteúdo estático no bucket S3..."
aws s3 cp ./$INDEX_FILE s3://$S3_BUCKET_NAME/
if [ $? -ne 0 ]; então
  echo "Erro ao carregar o conteúdo no bucket S3."
  exit 1
fi

echo "Conteúdo carregado com sucesso no bucket S3."

# 3. Criar um Origin Access Identity (OAI)
echo "Criando o Origin Access Identity..."
OAI_ID=$(aws cloudfront create-cloud-front-origin-access-identity \
  --cloudfront-origin-access-identity-config "{\"Comment\":\"$OAI_COMMENT\"}" \
  --query 'CloudFrontOriginAccessIdentity.Id' \
  --output text)

if [ $? -ne 0 ]; então
  echo "Erro ao criar o Origin Access Identity."
  exit 1
fi

echo "Origin Access Identity criado com sucesso. ID: $OAI_ID"
echo $OAI_ID > $OAI_ID_FILE

# Obter o Canonical User ID para atualizar a política do bucket S3
OAI_CANONICAL_USER_ID=$(aws cloudfront get-cloud-front-origin-access-identity \
  --id $OAI_ID \
  --query 'CloudFrontOriginAccessIdentity.S3CanonicalUserId' \
  --output text)

# Atualizar a política do bucket S3
echo "Atualizando a política do bucket S3..."
aws s3api put-bucket-policy \
  --bucket $S3_BUCKET_NAME \
  --policy '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "CanonicalUser": "'"$OAI_CANONICAL_USER_ID"'"
        },
        "Action": "s3:GetObject",
        "Resource": "arn:aws:s3:::'"$S3_BUCKET_NAME"'/*"
      }
    ]
  }'

if [ $? -ne 0 ]; então
  echo "Erro ao atualizar a política do bucket S3."
  exit 1
fi

echo "Política do bucket S3 atualizada com sucesso."

# 4. Criar a distribuição CloudFront
echo "Criando a distribuição CloudFront..."
DISTRIBUTION_ID=$(aws cloudfront create-distribution \
  --distribution-config '{
      "CallerReference": "unique-string",
      "Aliases": {
          "Quantity": 0
      },
      "DefaultRootObject": "index.html",
      "Origins": {
          "Quantity": 1,
          "Items": [
              {
                  "Id": "S3-'$S3_BUCKET_NAME'",
                  "DomainName": "'$S3_BUCKET_NAME'.s3.amazonaws.com",
                  "S3OriginConfig": {
                      "OriginAccessIdentity": "origin-access-identity/cloudfront/'$OAI_ID'"
                  }
              }
          ]
      },
      "DefaultCacheBehavior": {
          "TargetOriginId": "S3-'$S3_BUCKET_NAME'",
          "ViewerProtocolPolicy": "allow-all",
          "AllowedMethods": {
              "Quantity": 7,
              "Items": [
                  "GET",
                  "HEAD",
                  "POST",
                  "PUT",
                  "PATCH",
                  "OPTIONS",
                  "DELETE"
              ],
              "CachedMethods": {
                  "Quantity": 2,
                  "Items": [
                      "GET",
                      "HEAD"
                  ]
              }
          },
          "ForwardedValues": {
              "QueryString": false,
              "Cookies": {
                  "Forward": "none"
              }
          },
          "MinTTL": 0
      },
      "Comment": "Distribuição para acessar o bucket S3",
      "Enabled": true
  }' \
  --query 'Distribution.Id' \
  --output text)

if [ $? -ne 0 ]; então
  echo "Erro ao criar a distribuição CloudFront."
  exit 1
fi

echo "Distribuição CloudFront criada com sucesso. ID: $DISTRIBUTION_ID"
echo $DISTRIBUTION_ID > $CLOUDFRONT_DISTRIBUTION_ID_FILE
