# Fila de testes em jogo

Regra (no `CLAUDE.md`, "Ciclo de teste"): o que é **crítico** (dinheiro, save, carregamento) vai no próximo lote, pequeno. O **não crítico** (UI, texto, estatística, log) acumula e é testado junto.

Para ler o log depois de cada lote:

```bash
# mostra as linhas do Beamazon e qualquer erro de Lua
grep -i "beamazon\|lua error\|stack traceback" ~/.local/share/BeamNG/BeamNG.drive/current/beamng.log | tail -60
```

Console do jogo: `~`, no modo GE Lua. Para acelerar: `beamazon_fleetSim.setSpeed(60)` (1 s de jogo = 1 min de frota).

## Crítico (próximo lote)

### 9. Vans pelo nível de Logística e preço com variação

No save `perfil2`, abra o console e rode `beamazon_fleetManager.status()`.

- **Esperado:** a primeira linha mostra `fleet: X/Y van(s) at Logistics level N, next van $P`. Y é 0 abaixo do nível 5, 1 a partir do 5, 2 a partir do 10 e 3 a partir do 15. P fica perto de $7.500.
- As vans que você já tem continuam trabalhando, mesmo acima do limite novo. Só a compra é bloqueada.
- Se o limite deixar, compre uma van pelo celular: o saldo cai exatamente P e o log mostra `next offer $...` com outro preço.
- Salve, recarregue e rode `status()` de novo: o `next van` é o mesmo de antes do save.
- No celular, no limite: o botão diz `Logistics level N unlocks a van` (ou `Van limit reached` no nível 15+), com o seu nível embaixo.

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
