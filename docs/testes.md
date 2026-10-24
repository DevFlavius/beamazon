# Fila de testes em jogo

Regra (no `CLAUDE.md`, "Ciclo de teste"): o que é **crítico** (dinheiro, save, carregamento) vai no próximo lote, pequeno. O **não crítico** (UI, texto, estatística, log) acumula e é testado junto.

Para ler o log depois de cada lote:

```bash
# mostra as linhas do Beamazon e qualquer erro de Lua
grep -i "beamazon\|lua error\|stack traceback" ~/.local/share/BeamNG/BeamNG.drive/current/beamng.log | tail -60
```

Console do jogo: `~`, no modo GE Lua. Para acelerar: `beamazon_fleetSim.setSpeed(60)` (1 s de jogo = 1 min de frota).

## Crítico (próximo lote)

### 2. Crédito antes do save

Num save **sem o modo cheats** (com cheats o saldo fica em $1.000.000.000.000 e não dá para conferir). Logo depois de uma viagem terminar (use `setSpeed(60)` para ter várias), salve o jogo pelo RLS. Volte ao menu e carregue esse save.

Já confirmado em 2026-10-24 (save `perfil2`, sem cheats): o pagamento pendente entra logo antes do save, e o save grava o saldo com ele ($49.346,83 no log e no `playerattributes.json`). Falta conferir o saldo ao recarregar.

- Também a conferir: o `setSpeed(60)` de uma sessão não passa mais para outra carreira carregada depois (corrigido em 2026-10-24).

- **Esperado:** o saldo ao carregar é igual ao saldo no momento do save. Nenhum dinheiro some e nenhum aparece em dobro.

### 3. Progresso offline

Salve, saia para o menu (ou feche o jogo) e espere uns 15 minutos de relógio. Carregue o save.

- **Esperado:** no log aparecem `fleet loaded: N van(s), 0.2 h away` e `offline progress: 0.2 h`. O livro-caixa ganha uma linha "Beamazon: offline deliveries (N)".
- O teto é de 8 h. Para testar, mude o relógio do PC ou só confira: fora mais de 8 h deve dar `8.0 h away`.

## Não crítico (acumula)

(vazio)

## Antes do release

### 7. Sem o RLS

Desative o RLS no gerenciador de mods, deixe o Beamazon ativo e abra a carreira normal.

- **Esperado:** o jogo e a carreira carregam. O log mostra `adapter loaded` e nenhuma linha `E` do Beamazon. Nada é cobrado nem pago.

### 8. O zip

Rode `scripts/pack.sh` e instale `dist/beamazon.zip` no lugar do link (tire o link de `mods/unpacked/` antes).

- **Esperado:** o mesmo comportamento do link. O zip tem só `lua/`, `scripts/`, `ui/` e `gameplay/`.

## Testado

| Data | O quê | Resultado |
|---|---|---|
| 2026-10-24 | Fase 0: `creditTest()` credita $1 | ok |
| 2026-10-24 | MVP: compra, entregas, pagamento no saldo, save e volta ao recarregar | ok, ~$142 por van-hora |
| 2026-10-24 | Celular do RLS abre (os erros de UI no log são do RLS) | ok |
| 2026-10-24 | Pagamento em lote: um `addMoney` por minuto e um logo antes do save | ok |
| 2026-10-24 | Limite de 3 vans: a 4ª recusada no console (`van limit reached (3)`) e no app | ok |
| 2026-10-24 | XP de Logística pela frota: 2 a 14 XP por pagamento, sem erro | ok |
| 2026-10-24 | App no celular: instalar, ver a frota, comprar van, voltar | ok |
| 2026-10-24 | Lucro por van-hora no `status()` e no app | ok, $229,59 em 3,7 van-horas (save com cheats) |
