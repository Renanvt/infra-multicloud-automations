# README — Transferir Arquivos do PC para uma VM no Google Cloud via Terminal

## Pré-requisitos

* Ter o Google Cloud SDK instalado
* Ter acesso à VM no Google Cloud
* Saber:

  * Nome da VM
  * Zona da VM
  * Usuário da VM

---

## 1. Abrir o terminal correto

No Windows, abra:

* **Google Cloud SDK Shell**
  ou
* **PowerShell**

⚠️ Não execute os comandos dentro da VM via SSH.

---

## 2. Fazer login no Google Cloud

```bash id="r1"
gcloud auth login
```

---

## 3. Selecionar o projeto

Ver projeto atual:

```bash id="r2"
gcloud config get-value project
```

Listar projetos:

```bash id="r3"
gcloud projects list
```

Selecionar projeto:

```bash id="r4"
gcloud config set project SEU_PROJECT_ID
```

---

## 4. Transferir arquivo do PC para a VM

### Estrutura do comando

```bash id="r5"
gcloud compute scp "CAMINHO_DO_ARQUIVO" USUARIO@VM:/DESTINO/ --zone=ZONA
```

---

## 5. Exemplo real

Arquivo local:

```text id="r6"
D:\workspace\infra\infra-openclaw\assistant-media.rar
```

VM:

```text id="r7"
openclaw-alobexpress
```

Usuário:

```text id="r8"
jonat
```

Zona:

```text id="r9"
us-central1-a
```

Comando:

```bash id="r10"
gcloud compute scp "D:\workspace\infra\infra-openclaw\assistant-media.rar" openclaw-alobexpress:/home/jonat/ --zone=us-central1-a
```

---

## 6. Acessar a VM

```bash id="r11"
gcloud compute ssh openclaw-alobexpress --zone=us-central1-a
```

---

## 7. Confirmar que o arquivo chegou

```bash id="r12"
ls -lh /home/jonat/
```

---

## 8. Mover arquivo para outra pasta da VM

Exemplo:

```bash id="r13"
sudo mv /home/jonat/assistant-media.rar /opt/alobexpress/
```

---

# Erros comuns

## Erro: `All sources must be local files when destination is remote`

Você executou o comando SCP dentro da VM.

✅ Execute no Windows local.

---

## Erro: `pscp: unable to open ~/: failure`

O `~/` não funciona corretamente no Windows com `pscp`.

✅ Use caminho absoluto:

```bash id="r14"
/home/jonat/
```

---

## Erro: `Request had insufficient authentication scopes`

Faça login novamente:

```bash id="r15"
gcloud auth login
```

E selecione o projeto:

```bash id="r16"
gcloud config set project SEU_PROJECT_ID
```

---

# Upload de pastas inteiras

Use `--recurse`:

```bash id="r17"
gcloud compute scp --recurse "D:\meu-projeto" openclaw-alobexpress:/home/jonat/ --zone=us-central1-a
```

---

# Dica útil

Para descobrir a zona da VM:

```bash id="r18"
gcloud compute instances list
```
