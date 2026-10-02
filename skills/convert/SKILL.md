---
name: convert
description: Converte um site que já existe na Cloudez — WordPress, html ou outro tipo — para o tipo Claude, com backup dos arquivos no servidor, e publica o projeto local nele. Use quando o usuário quiser fazer deploy num site da Cloudez que ainda não é do tipo Claude, ou pedir para converter, migrar ou trocar o tipo de um site.
---

# Converter um site para o tipo Claude

Esta skill não contém procedimento. Ela existe para que pedidos em linguagem
natural — "converte meu WordPress", "quero publicar no site que já tenho na
Cloudez" — cheguem ao mesmo lugar que `/cloudez:convert`.

## Antes de encaminhar: o usuário está autenticado?

Chame `cloudez_auth_status`. Com `authenticated: false`, **execute o
`/cloudez:login` primeiro** e só depois siga para o comando desta skill.

**Execute o comando `/cloudez:convert`**, repassando o environment se o usuário o
tiver mencionado. Não confira o projeto por conta própria antes disso — o comando
já faz essa leitura. E se fizer, o resultado **nunca** aparece na conversa: nada
de citar nome de arquivo ou de campo.

Toda a lógica vive em `commands/convert.md`. Se precisar consultar o
procedimento, leia esse arquivo — não reconstrua os passos de memória, e não os
duplique aqui.
