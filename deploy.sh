#!/bin/bash

BUCKET_NAME='treinamentoiteris'
REGION="us-east-1"
FILE='index.html'

# Criar um Bucket na região correta
echo "Criando S3 Bucket $BUCKET_NAME..."
aws s3api create-bucket --bucket $BUCKET_NAME --region $REGION 

# Upload de arquivo no S3 bucket
echo "Realizando o upload do arquivo..."
aws s3 cp $FILE s3://$BUCKET_NAME/

# Criar CloudFront Origin Access Control
echo "Criando OAC..."
aws cloudfront create-origin-access-control \
    --origin-access-control-config '{
        "Name": "MeuOAC",
        "Description": "OAC para acesso seguro ao bucket S3",
        "SigningProtocol": "sigv4",
        "SigningBehavior": "always",
        "OriginAccessControlOriginType": "s3"
    }' > oac_response.json

# Extrair ID do OAC
OAC_ID=$(cat oac_response.json | jq -r '.OriginAccessControl.Id')
echo "OAC criado com ID: $OAC_ID"

# Criar uma CloudFront Distribution (sem o OAC inicialmente)
echo "Criando CloudFront Distribution..."
aws cloudfront create-distribution \
    --origin-domain-name $BUCKET_NAME.s3.amazonaws.com \
    --default-root-object index.html \
    --query 'Distribution.{Id:Id}' --output json > cf_response.json

# Extrair ID da distribuição CloudFront
ID_CLOUDFRONT=$(cat cf_response.json | jq -r '.Id')
echo "CloudFront Distribution criada com ID: $ID_CLOUDFRONT"

# Obter a configuração atual da distribuição para edição
echo "Atualizando a CloudFront Distribution para incluir o OAC..."
aws cloudfront get-distribution-config --id $ID_CLOUDFRONT > cf_config.json

ETAG=$(cat cf_config.json | jq -r '.ETag')

# Modificar a configuração da distribuição para usar o OAC
CONFIG=$(cat cf_config.json | jq '.DistributionConfig | .Origins.Items[0].S3OriginConfig |= {OriginAccessIdentity: ""} | .Origins.Items[0] += {"OriginAccessControlId": "'$OAC_ID'"}')

# Atualizar a distribuição com a nova configuração
aws cloudfront update-distribution --id $ID_CLOUDFRONT \
    --distribution-config "$CONFIG" \
    --if-match $ETAG

# Atualizar a política do bucket S3 para permitir o acesso apenas via OAC do CloudFront
echo "Atualizando a política do bucket para restringir o acesso..."
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

POLICY=$(cat <<EOF
{
    "Version": "2008-10-17",
    "Statement": [
    {
    "Sid": "AllowCloudFrontServicePrincipal",
    "Effect": "Allow",
    "Principal": {
        "Service": "cloudfront.amazonaws.com"
    },
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::$BUCKET_NAME/*",
    "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "arn:aws:cloudfront::$ACCOUNT_ID:distribution/$ID_CLOUDFRONT"
        }
      }
    }
  ]
}
EOF
)

# Aplicar a política no bucket
aws s3api put-bucket-policy --bucket $BUCKET_NAME --policy "$POLICY"

echo "Configuração finalizada com sucesso!"
