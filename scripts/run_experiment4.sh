#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

LAB_DIR="${LAB_DIR:-${REPO_ROOT}/pki_lab}"
CA_PASS="${CA_PASS:-}"
SERVER_CN="${SERVER_CN:-www.testlab.com}"

if [[ -z "${CA_PASS}" ]]; then
  echo "ERROR: 请先设置 CA_PASS 环境变量。"
  echo "示例：CA_PASS='Str0ng-Passw0rd!2026' bash scripts/run_experiment4.sh"
  exit 1
fi

ROOT_CA_SUBJ="/C=CN/ST=SC/L=CD/O=PKI_LAB_Security/OU=NetSec/CN=Root_CA/emailAddress=ca@pki.lab"
SERVER_SUBJ="/C=CN/ST=SC/L=CD/O=PKI_LAB_Security/OU=NetSec/CN=${SERVER_CN}"

echo "[1/5] 初始化实验目录：${LAB_DIR}"
if [[ "${LAB_DIR}" != "${REPO_ROOT}/"* ]]; then
  echo "ERROR: LAB_DIR 必须位于仓库目录下：${REPO_ROOT}"
  exit 1
fi
if [[ "${LAB_DIR}" == "/" || "${LAB_DIR}" == "/root" || "${LAB_DIR}" == "/home" || "${LAB_DIR}" == "${REPO_ROOT}" ]]; then
  echo "ERROR: LAB_DIR 目录不安全：${LAB_DIR}"
  exit 1
fi
if [[ -d "${LAB_DIR}" ]]; then
  rm -rf "${LAB_DIR}"
fi
mkdir -p "${LAB_DIR}"
cd "${LAB_DIR}"

mkdir -p ca/{certs,private,newcerts,crl}
touch ca/index.txt
echo 01 > ca/serial

mkdir -p demoCA/newcerts
touch demoCA/index.txt
echo 01 > demoCA/serial
echo 01 > demoCA/crlnumber

cat > openssl_ca.cnf <<EOF
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = ./demoCA
new_certs_dir     = ./demoCA/newcerts
database          = ./demoCA/index.txt
serial            = ./demoCA/serial
crlnumber         = ./demoCA/crlnumber
certificate       = ./ca/root_ca.crt
private_key       = ./ca/private/root_ca.key
default_md        = sha256
default_days      = 365
default_crl_days  = 30
policy            = policy_loose
x509_extensions   = usr_cert
copy_extensions   = copy
crl               = ./ca/crl/revoke_crl.pem

[ policy_loose ]
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ usr_cert ]
basicConstraints = CA:FALSE
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
EOF

echo "[2/5] 生成根 CA 私钥和根证书"
openssl genrsa -aes256 -passout "pass:${CA_PASS}" -out ca/private/root_ca.key 2048
openssl req -new -x509 -days 3650 \
  -key ca/private/root_ca.key -passin "pass:${CA_PASS}" \
  -out ca/root_ca.crt -subj "${ROOT_CA_SUBJ}"

echo "[3/5] 生成服务器私钥、CSR，并由根 CA 签发证书"
openssl genrsa -out server.key 2048
openssl req -new -key server.key -out server.csr \
  -subj "${SERVER_SUBJ}" -addext "subjectAltName=DNS:${SERVER_CN},DNS:localhost,IP:127.0.0.1"

openssl ca -batch -config openssl_ca.cnf \
  -in server.csr -out server.crt -days 365 \
  -cert ca/root_ca.crt -keyfile ca/private/root_ca.key \
  -passin "pass:${CA_PASS}" -extensions usr_cert

echo "[4/5] 证书验证与格式转换"
openssl verify -CAfile ca/root_ca.crt server.crt
openssl x509 -in server.crt -outform DER -out server.der
openssl pkcs12 -export -in server.crt -inkey server.key \
  -out server.pfx -passout "pass:${CA_PASS}"
openssl x509 -in server.crt -pubkey -noout > server_pub.key

echo "[5/5] 证书吊销与 CRL 验证"
openssl ca -config openssl_ca.cnf -revoke server.crt \
  -cert ca/root_ca.crt -keyfile ca/private/root_ca.key \
  -passin "pass:${CA_PASS}"
openssl ca -config openssl_ca.cnf -gencrl -out ca/crl/revoke_crl.pem \
  -cert ca/root_ca.crt -keyfile ca/private/root_ca.key \
  -passin "pass:${CA_PASS}"

set +e
openssl verify -CAfile ca/root_ca.crt -CRLfile ca/crl/revoke_crl.pem -crl_check server.crt
VERIFY_RC=$?
set -e

if [[ "${VERIFY_RC}" -eq 0 ]]; then
  echo "ERROR: 证书已吊销，但校验未失败。"
  exit 1
fi

echo ""
echo "实验完成。输出目录：${LAB_DIR}"
echo "关键文件："
echo "  ca/private/root_ca.key"
echo "  ca/root_ca.crt"
echo "  server.key"
echo "  server.csr"
echo "  server.crt"
echo "  server.der"
echo "  server.pfx"
echo "  server_pub.key"
echo "  ca/crl/revoke_crl.pem"
