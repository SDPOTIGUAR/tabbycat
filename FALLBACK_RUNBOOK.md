# Fallback local de emergência — Tabbycat

Sobe o stack completo (db + redis + web + worker) neste notebook, usando as
mesmas imagens/config do deploy principal. Só entra em uso se o Oracle Cloud
cair durante um torneio.

HTTP puro, sem TLS/certificado — decisão deliberada: sem domínio próprio e
com a Vivo bloqueando as portas 80/443 de entrada (ver seção abaixo), não dá
pra ter certificado real aqui, e certificado autoassinado só gera aviso
assustador pros participantes sem ganho real de segurança pro contexto (torneio
interno, baixo risco). Login/senha trafegam sem criptografia — aceito
conscientemente.

## Subir

```bash
cd "TABBY SDP"
podman-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

Não precisa de nenhuma variável de ambiente — `web` já publica a porta 8000
no host por padrão.

## Derrubar

```bash
podman-compose -f docker-compose.yml -f docker-compose.prod.yml down
```

## Roteador (Vivo Box / Inventus RTF8225VW)

Painel em `192.168.15.1`, login `admin` + senha na etiqueta do aparelho.
Menu: **Configurações → Rede Local → Redirecionar Portas**.

| Campo | Valor |
|---|---|
| Nome da Regra | `tabbycat-http` |
| Protocolo | TCP |
| Porta Externa | `8443` |
| Porta Interna | `8000` |
| IP Interno | `192.168.15.7` (IP local deste notebook — conferir se mudou) |

**Por que porta externa 8443 e não 80:** a Vivo bloqueia permanentemente as
portas de entrada "clássicas" (80, 443, 21, 23, 25, 53 e demais abaixo de
1024) no nível da própria operadora pra planos residenciais — nenhuma
configuração de roteador contorna isso, só existe desbloqueio em link
dedicado/empresarial. Portas acima de 1024 passam livremente. Confirmado na
prática: com porta externa 443 a conexão nunca chegava (timeout); com 8443
funcionou.

O painel gera automaticamente uma regra de firewall ("pinhole") junto com o
redirecionamento — não precisa mexer na aba Firewall separadamente.

## URL fixa (DuckDNS)

O IP é dinâmico — pra endereço estável o suficiente pra mandar login por
e-mail com antecedência, o `docker-compose.duckdns.yml` sobe um container
que mantém `sdp-viii-interno.duckdns.org` sempre apontando pro IP atual
desta conexão, checando a cada poucos minutos. Sem isso, o IP pode mudar
entre o envio dos e-mails e o dia do evento.

```bash
DUCKDNS_TOKEN=<token de duckdns.org, nunca commitar> \
  podman-compose -f docker-compose.duckdns.yml up -d
```

Esse container precisa continuar rodando (não só no dia do evento — desde
antes de mandar os e-mails de login).

Endereço final pra divulgar:

**http://sdp-viii-interno.duckdns.org:8443/**

(testar sempre por fora da rede de casa — celular com Wi-Fi desligado — o
roteador não suporta hairpin NAT, então acessar de dentro de casa pelo
próprio IP/hostname público trava, mesmo estando tudo certo).

## Checklist de hardening antes de ativar

- [ ] Firewalld local: confirmar que a porta 8000 (só ela, é a única usada
      agora) está liberada.
      ```bash
      ! sudo firewall-cmd --add-port=8000/tcp --permanent
      ! sudo firewall-cmd --reload
      ```
      Pra desativar depois:
      ```bash
      ! sudo firewall-cmd --remove-port=8000/tcp --permanent
      ! sudo firewall-cmd --reload
      ```
- [ ] Auditar o que mais está escutando no notebook (KDE Connect, Samba,
      CUPS etc.) — nada disso pode ficar alcançável de fora além da porta
      forwardada.
- [ ] `DEBUG=0` confirmado (já é o padrão do `docker-compose.prod.yml` —
      não mudar isso durante o teste).
- [ ] Backup do Postgres antes de ativar (`podman exec tabbysdp_db_1 pg_dump
      -U tabbycat tabbycat > backup.sql`) e depois de encerrar a emergência.
- [ ] Fedora atualizado (`sudo dnf upgrade`) antes de expor.
- [ ] Janela de exposição curta: só ativa o port-forward no roteador durante
      a emergência de fato; desativa (e reverte o firewalld) assim que o
      Oracle voltar.

## O que falta pra isso funcionar de ponta a ponta

- Cadastro na Oracle Cloud (Always Free) — já feito.
- Regra de redirecionamento de porta no roteador — já feita e testada
  (funcionando via 4G externo, confirmado).
- Hostname fixo via DuckDNS — já feito e testado (`sdp-viii-interno.duckdns.org`).
