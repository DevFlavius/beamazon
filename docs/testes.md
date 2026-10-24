# Fila de testes em jogo

Regra (no `CLAUDE.md`, "Ciclo de teste"): o que é **crítico** (dinheiro, save, carregamento) vai no próximo lote, pequeno. O **não crítico** (UI, texto, estatística, log) acumula e é testado junto.

Para ler o log depois de cada lote:

```bash
# mostra as linhas do Beamazon e qualquer erro de Lua
grep -i "beamazon\|lua error\|stack traceback" ~/.local/share/BeamNG/BeamNG.drive/current/beamng.log | tail -60
```

Console do jogo: `~`, no modo GE Lua. Para acelerar: `beamazon_fleetSim.setSpeed(60)` (1 s de jogo = 1 min de frota).

## Crítico (próximo lote)

### 12. Teto offline de 2 h

Salve, feche o jogo e volte depois de mais de 2 horas (pode ser no dia seguinte).

- **Esperado:** o log mostra `fleet loaded: N van(s), 2.0 h away` (nunca mais que 2.0) e um lançamento `offline deliveries` de ~$10.000 por van.

### 13b. Sede soma 5 vagas às vans pessoais

Ctrl+L no save onde a sede já foi comprada e rode `beamazon_fleetManager.status()`.

- **Esperado:** com nível 15 ou mais, o limite é 8 (3 pessoais + 5 da sede). O celular mostra `Company HQ · +5 fleet slots` e deixa comprar até a 8ª van.

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
| 2026-10-24 | Rendimento com `setSpeed(60)`: entre os saves autosave2 e autosave3, 2 vans em 6,24 van-horas renderam $30.948 | ok, $4.960 por van-hora (meta ~$5.000) |
| 2026-10-24 | A oferta da van sobrevive ao save | ok |
| 2026-10-24 | Venda de van pelo celular e pelo console | ok |
| 2026-10-24 | Sede: ponto no mapa grande, rota, cartão, compra com nível 20 (XP pelo console) | ok, mas o limite ficou em 5; corrigido para pessoais + 5 (item 13b). Falta o objeto 3D do notebook |
