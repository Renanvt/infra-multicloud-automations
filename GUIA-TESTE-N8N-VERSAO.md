# 🧪 Guia: Testar Versões do n8n (Abordagem Senior)

## 🎯 Objetivo

Encontrar a **última versão estável do n8n** que funciona sem o bug do `{{BASE_PATH}}` no seu ambiente.

## 📋 Pré-requisitos

- ✅ Workflows salvos/baixados localmente (backup feito)
- ✅ Acesso SSH à VM
- ✅ n8n atualmente rodando na versão 1.100.0

## 🚀 Passos na VM

### 1. Conectar na VM e preparar ambiente

```bash
ssh root@34.42.171.75
cd /opt/infra/alobexpress
```

### 2. Fazer pull do repositório atualizado

```bash
git pull origin main
```

### 3. Copiar script de teste para pasta correta

```bash
# Copiar do repositório local para pasta de infra
cp test-n8n-version.sh /opt/infra/alobexpress/
chmod +x /opt/infra/alobexpress/test-n8n-version.sh
```

### 4. Copiar YAML atualizado

```bash
# Copiar YAML atualizado com versão 2.41.6 de teste
cp /opt/infra/alobexpress/vm/08.n8n-editor.yaml /opt/infra/alobexpress/08.n8n-editor.yaml
```

## 🧪 Teste de Versões

### Teste 1: Versão 2.41.6 (Última Stable)

```bash
cd /opt/infra/alobexpress
bash test-n8n-version.sh 2.41.6
```

**O script vai:**
1. Mostrar versão atual e versão de teste
2. Pedir confirmação
3. Atualizar o serviço
4. Aguardar convergência
5. Pedir que você teste manualmente no navegador

**No navegador:**
1. Aguarde ~30 segundos
2. Limpe cache (Ctrl+Shift+Delete → Cache/Cookies)
3. Acesse: `https://editorn8n.alobexpress.com.br`
4. Verifique:
   - ✅ Frontend carrega (não redireciona para `/%7B%7BBASE_PATH%7D%7D/`)
   - ✅ Consegue fazer login
   - ✅ Workflows aparecem

**Informe ao script:** `funcionou` ou `falhou`

---

### Se 2.41.6 FUNCIONAR ✅

Perfeito! Agora vamos fazer build da imagem custom:

```bash
# 1. Atualizar Dockerfile
sed -i 's/FROM n8nio\/n8n:.*/FROM n8nio\/n8n:2.41.6 AS base/' /opt/alobexpress/n8n-custom/Dockerfile

# 2. Build da imagem custom
cd /opt/alobexpress/n8n-custom
docker build --no-cache --pull -t alobexpress/n8n-custom:2.41.6 .

# 3. Atualizar YAML para usar custom
sed -i 's|image: n8nio/n8n:2.41.6|image: alobexpress/n8n-custom:2.41.6|' /opt/infra/alobexpress/08.n8n-editor.yaml

# 4. Deploy com imagem custom
docker stack deploy -c /opt/infra/alobexpress/08.n8n-editor.yaml n8n_editor

# 5. Atualizar workers e webhooks
docker service update --image alobexpress/n8n-custom:2.41.6 n8n_workers_n8n_workers
docker service update --image alobexpress/n8n-custom:2.41.6 n8n_webhooks_n8n_webhooks
```

**Commit no repositório:**
```bash
cd /opt/infra/alobexpress
git add n8n-custom/Dockerfile vm/08.n8n-editor.yaml
git commit -m "feat(n8n): atualizado para v2.41.6 - versão estável sem bug BASE_PATH"
git push origin main
```

✅ **PRONTO!** n8n rodando na última versão com FFmpeg, Git e Python!

---

### Se 2.41.6 FALHAR ❌

O script oferece reverter automaticamente. Depois teste versões anteriores:

```bash
# Testar versão 2.30.0
bash test-n8n-version.sh 2.30.0

# Testar versão 2.20.0
bash test-n8n-version.sh 2.20.0

# Testar versão 2.10.0
bash test-n8n-version.sh 2.10.0

# Se todas falharem, voltar para 1.100.0 (sabemos que funciona)
bash test-n8n-version.sh 1.100.0
```

**Versões estratégicas para testar:**
- `2.41.6` ← última stable (outubro 2026)
- `2.30.0` ← versão intermediária
- `2.20.0` ← versão intermediária
- `2.10.0` ← primeira 2.x mais recente
- `2.0.0` ← primeira da série 2.x
- `1.100.0` ← **sabemos que funciona**

---

## 🔍 Verificação de Logs

Se algo der errado, verifique os logs:

```bash
# Logs do editor
docker service logs --tail 100 -f n8n_editor_n8n_editor

# Status do serviço
docker service ps n8n_editor_n8n_editor

# Inspecionar serviço
docker service inspect n8n_editor_n8n_editor --pretty
```

---

## 📊 Tabela de Compatibilidade

| Versão   | Frontend | Login | Schema | Status            |
|----------|----------|-------|--------|-------------------|
| 2.41.6   | ❓       | ❓    | ❓     | **A TESTAR**      |
| 2.30.0   | ❓       | ❓    | ❓     | A testar          |
| 2.20.0   | ❓       | ❓    | ❓     | A testar          |
| 2.10.0   | ❓       | ❓    | ❓     | A testar          |
| 2.0.0    | ❓       | ❓    | ❓     | A testar          |
| 1.100.0  | ✅       | ✅    | ✅     | **FUNCIONA** ✓    |
| 1.82.1   | ✅       | ✅    | ✅     | Funciona          |
| 1.80.0   | ✅       | ✅    | ✅     | Funciona          |

**Legenda:**
- ✅ = Confirmado funcionando
- ❌ = Confirmado com bug
- ❓ = Não testado

---

## 🎯 Resultado Esperado

Ao final, você terá:

1. ✅ n8n rodando na **última versão estável disponível**
2. ✅ Imagem custom com **FFmpeg, Git e Python**
3. ✅ Todos os serviços (editor, worker, webhook) na mesma versão
4. ✅ Workflows funcionando perfeitamente
5. ✅ Data Tables disponível
6. ✅ Documentação atualizada no repositório

---

## 🆘 Troubleshooting

### Problema: Frontend não carrega (página branca)

**Solução:**
```bash
# Limpar cache do navegador
# Verificar logs do container
docker service logs --tail 50 n8n_editor_n8n_editor
```

### Problema: Erro de login (schema)

**Solução:**
```bash
# Verificar se coluna 'role' existe
docker exec $(docker ps -q -f name=postgres_postgres) psql -U postgres -d n8n -c "\d+ \"user\""

# Se não existir, adicionar:
docker exec $(docker ps -q -f name=postgres_postgres) psql -U postgres -d n8n -c "ALTER TABLE \"user\" ADD COLUMN IF NOT EXISTS role VARCHAR(32) DEFAULT 'global:member';"
```

### Problema: Workflows com interrogação (?)

**Causa:** Community nodes não instalados (n8n-nodes-evolution-api, etc.)

**Solução:**
```bash
# Reinstalar community nodes
docker exec -it $(docker ps -q -f name=n8n_editor) npm install n8n-nodes-evolution-api
docker service update --force n8n_editor_n8n_editor
```

---

## 📞 Suporte

- **GitHub Issues n8n:** https://github.com/n8n-io/n8n/issues
- **Community Forum:** https://community.n8n.io
- **Documentação:** https://docs.n8n.io

---

**Boa sorte! 🚀**
