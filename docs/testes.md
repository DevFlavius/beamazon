# Fila de testes em jogo

Regra (no `CLAUDE.md`, "Ciclo de teste"): o que é **crítico** (dinheiro, save, carregamento) vai no próximo lote, pequeno. O **não crítico** (UI, texto, estatística, log) acumula e é testado junto.

Para ler o log depois de cada lote:

```bash
# mostra as linhas do Beamazon e qualquer erro de Lua
grep -i "beamazon\|lua error\|stack traceback" ~/.local/share/BeamNG/BeamNG.drive/current/beamng.log | tail -60
```

Console do jogo: `~`, no modo GE Lua. Para acelerar: `beamazon_fleetSim.setSpeed(60)` (1 s de jogo = 1 min de frota).

## Crítico (próximo lote)

### 9b. A oferta da van sobrevive ao save

O resto do item 9 passou. Falta: salve, saia para o menu, carregue o mesmo save e rode `beamazon_fleetManager.status()`.

- **Esperado:** o `next van $...` é o mesmo de antes do save.

### 10. Venda de van

Ctrl+L, depois no console: `beamazon_fleetManager.status()`. Cada van mostra `(id N)` e `sells for $X`.

- **Esperado:** as suas vans, compradas a $1.000 antes do preço ser gravado, valem $6.375 (85% de $7.500) vezes o mercado.
- No celular, toque em `Sell` numa van: o botão vira `Tap again to sell for $X`. Espere 4 s sem tocar: ele volta ao normal.
- Toque duas vezes: a van some, o saldo sobe exatamente $X, e o log mostra `sellVan: Van N sold for $X`.
- Salve e recarregue: a van vendida não volta.

### 11. Rendimento de ~$5.000 por van-hora

Ctrl+L, depois no console: `beamazon_fleetSim.setSpeed(60)` e espere 3 ou 4 minutos (cada minuto real = 1 hora de frota).

- **Esperado:** cada linha `addMoney` (uma por minuto) fica perto de $5.000 por van (com 3 vans, ~$15.000; varia bastante de um minuto para o outro).
- Depois volte com `beamazon_fleetSim.setSpeed(1)`. O `status()` ainda mistura as horas antigas a $193, então o "per van-hour" dele sobe devagar; confira pelas linhas `addMoney`.

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
| 2026-10-24 | Crédito antes do save: save `perfil2` sem cheats grava $49.346,83 e o save recarrega com esse saldo | ok |
| 2026-10-24 | Progresso offline: 0,2 h fora, `offline progress: 0.2 h` e $58,24 num lançamento só | ok |
| 2026-10-24 | Vans pelo nível de Logística: nível 2 dá limite 0, as 3 vans antigas seguem trabalhando, oferta $5.999; app e `status()` sem erro (depois da correção `e91b7ec`) | ok |
