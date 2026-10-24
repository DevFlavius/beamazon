# Fila de testes em jogo

Regra (no `CLAUDE.md`, "Ciclo de teste"): o que é **crítico** (dinheiro, save, carregamento) vai no próximo lote, pequeno. O **não crítico** (UI, texto, estatística, log) acumula e é testado junto.

Para ler o log depois de cada lote:

```bash
# mostra as linhas do Beamazon e qualquer erro de Lua
grep -i "beamazon\|lua error\|stack traceback" ~/.local/share/BeamNG/BeamNG.drive/current/beamng.log | tail -60
```

Console do jogo: `~`, no modo GE Lua. Para acelerar: `beamazon_fleetSim.setSpeed(60)` (1 s de jogo = 1 min de frota).

## Crítico (próximo lote)

### 1. Pagamento em lote

Num save com pelo menos 1 van, jogue uns 3 minutos.

- **Esperado:** no log, no máximo uma linha `addMoney: ... (balance: ...)` por minuto, e o saldo sobe junto. O livro-caixa do RLS mostra "Beamazon: fleet deliveries (N)", e não uma linha por viagem.

### 2. Crédito antes do save

Logo depois de uma viagem terminar (use `setSpeed(60)` para ter várias), salve o jogo pelo RLS. Volte ao menu e carregue esse save.

- **Esperado:** o saldo ao carregar é igual ao saldo no momento do save. Nenhum dinheiro some e nenhum aparece em dobro.

### 3. Progresso offline

Salve, saia para o menu (ou feche o jogo) e espere uns 15 minutos de relógio. Carregue o save.

- **Esperado:** no log aparecem `fleet loaded: N van(s), 0.2 h away` e `offline progress: 0.2 h`. O livro-caixa ganha uma linha "Beamazon: offline deliveries (N)".
- O teto é de 8 h. Para testar, mude o relógio do PC ou só confira: fora mais de 8 h deve dar `8.0 h away`.

## Não crítico (acumula)

### 4. App no celular

Instale o app "Beamazon" pela App Store do celular do RLS e abra.

- **Esperado:** aparece o resumo (vans, entregas, lucro), cada van com a barra de progresso e o botão "Buy a van".
- Com dinheiro, o botão compra uma van e cobra o preço. Sem dinheiro, ele mostra "Not enough money for a van." e não cobra nada.
- O botão voltar leva à tela inicial do celular.

### 5. Lucro por van-hora

Com `setSpeed(60)`, espere 1 minuto por van e rode `beamazon_fleetManager.status()`.

- **Esperado:** o log mostra `net $X per van-hour over Y van-hours`. O app mostra "$X profit per van-hour" abaixo do resumo.
- Num save antigo, esse número começa do zero (o save não tinha a contagem de horas). É o número que os irmãos usam para decidir o balanceamento.

## Antes do release

### 6. Sem o RLS

Desative o RLS no gerenciador de mods, deixe o Beamazon ativo e abra a carreira normal.

- **Esperado:** o jogo e a carreira carregam. O log mostra `adapter loaded` e nenhuma linha `E` do Beamazon. Nada é cobrado nem pago.

### 7. O zip

Rode `scripts/pack.sh` e instale `dist/beamazon.zip` no lugar do link (tire o link de `mods/unpacked/` antes).

- **Esperado:** o mesmo comportamento do link. O zip tem só `lua/`, `scripts/`, `ui/` e `gameplay/`.

## Testado

| Data | O quê | Resultado |
|---|---|---|
| 2026-10-24 | Fase 0: `creditTest()` credita $1 | ok |
| 2026-10-24 | MVP: compra, entregas, pagamento no saldo, save e volta ao recarregar | ok, ~$142 por van-hora |
| 2026-10-24 | Celular do RLS abre (os erros de UI no log são do RLS) | ok |
