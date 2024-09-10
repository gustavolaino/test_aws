#!/bin/bash

# Variáveis
S3_BUCKET_NAME="treinamentoiteris"
CLOUDFRONT_DISTRIBUTION_ID_FILE="cloudfront_distribution_id.txt"
INDEX_FILE="index.html"
OAC_NAME="MyOAC"
REGION="us-east-1"

# 1. Provisionar o bucket S3
echo "Criando o bucket S3..."
aws s3api create-bucket --bucket $S3_BUCKET_NAME --region $REGION
if [ $? -ne 0 ]; then
  echo "Erro ao criar o bucket S3."
  exit 1
fi

echo "Bucket S3 criado com sucesso: $S3_BUCKET_NAME"

# 2. Carregar o conteúdo estático no bucket S3
echo "Carregando o conteúdo estático no bucket S3..."
aws s3 cp $INDEX_FILE s3://$S3_BUCKET_NAME/
if [ $? -ne 0 ]; then
  echo "Erro ao carregar o conteúdo no bucket S3."
  exit 1
fi

echo "Conteúdo carregado com sucesso no bucket S3."

# 3. Criar o Origin Access Control (OAC)
echo "Criando o Origin Access Control (OAC)..."
OAC_RESPONSE=$(aws cloudfront create-origin-access-control \
  --origin-access-control-config Name=$OAC_NAME,Description="OAC para $S3_BUCKET_NAME",OriginAccessControlOriginType=s3,SigningBehavior=sigv4,SigningProtocol=sigv4)
if [ $? -ne 0 ]; then
  echo "Erro ao criar o Origin Access Control (OAC)."
  exit 1
fi

# Extrair o ID do OAC usando jq
OAC_ID=$(echo $OAC_RESPONSE | jq -r '.OriginAccessControl.Id')
echo "OAC criado com ID: $OAC_ID"

# 4. Configurar a distribuição CloudFront com o OAC
echo "Criando a distribuição CloudFront..."
DISTRIBUTION_ID=$(aws cloudfront create-distribution \
  --origin-domain-name "$S3_BUCKET_NAME.s3.amazonaws.com" \
  --default-root-object "index.html" \
  --origin-access-control-id $OAC_ID \
  --query 'Distribution.Id' \
  --output text)
if [ $? -ne 0 ]; then
  echo "Erro ao criar a distribuição CloudFront."
  exit 1
fi

echo "Distribuição CloudFront criada com sucesso. ID: $DISTRIBUTION_ID"
echo $DISTRIBUTION_ID > $CLOUDFRONT_DISTRIBUTION_ID_FILE

# 5. Bloquear acesso público ao bucket S3
echo "Bloqueando acesso público ao bucket S3..."
aws s3api put-bucket-policy --bucket $S3_BUCKET_NAME --policy "{
  \"Version\": \"2012-10-17\",
  \"Statement\": [
    {
      \"Effect\": \"Allow\",
      \"Principal\": {
        \"Service\": \"cloudfront.amazonaws.com\"
      },
      \"Action\": \"s3:GetObject\",
      \"Resource\": \"arn:aws:s3:::$S3_BUCKET_NAME/*\",
      \"Condition\": {
        \"StringEquals\": {
          \"AWS:SourceArn\": \"arn:aws:cloudfront::$ACCOUNT_ID:distribution/$DISTRIBUTION_ID\"
        }
      }
    }
  ]
}"
if [ $? -ne 0 ]; then
  echo "Erro ao bloquear acesso público ao bucket S3."
  exit 1
fi

echo "Acesso público bloqueado com sucesso para o bucket S3."

echo "Configuração concluída."
