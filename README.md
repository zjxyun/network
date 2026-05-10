# network

本仓库已补充《实验4-基于OpenSSL的PKI构建实验》可复现实验代码，覆盖以下模块：

1. 环境初始化 + 根 CA 搭建  
2. 服务器私钥与 CSR 生成  
3. 根 CA 签发服务器证书  
4. 证书验证与格式转换  
5. 证书吊销、CRL 生成与吊销验证  

## 使用方式

```bash
# 在仓库根目录执行
cd <your-repo-path>/network
CA_PASS='Str0ng-Passw0rd!2026' bash ./scripts/run_experiment4.sh
```

可选环境变量：

- `LAB_DIR`：实验输出目录（默认：`$PWD/pki_lab`）
- `CA_PASS`：根 CA 私钥与 PFX 口令（必填）
- `SERVER_CN`：服务器证书 CN（默认：`www.testlab.com`）

示例：

```bash
LAB_DIR=./pki_lab_demo \
CA_PASS='Str0ng-Passw0rd!2026' \
SERVER_CN=www.testlab.com \
bash ./scripts/run_experiment4.sh
```

## 关键输出文件

- 根 CA 私钥：`ca/private/root_ca.key`
- 根 CA 证书：`ca/root_ca.crt`
- 服务器私钥：`server.key`
- 证书请求：`server.csr`
- 服务器证书：`server.crt`
- DER 证书：`server.der`
- PFX 证书包：`server.pfx`
- 服务器公钥：`server_pub.key`
- CRL 吊销列表：`ca/crl/revoke_crl.pem`

## 结果判定

脚本会自动执行以下检查：

- `openssl verify -CAfile ca/root_ca.crt server.crt` 返回 `OK`
- 吊销后执行  
  `openssl verify -CAfile ca/root_ca.crt -CRLfile ca/crl/revoke_crl.pem -crl_check server.crt`  
  返回 `certificate revoked`（预期失败）
