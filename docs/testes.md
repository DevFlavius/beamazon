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

### 14. Empresa: melhorias, motorista e caminhão (dinheiro e save)

No save com a sede. Dê XP de empresa para testar: rode a frota acelerada (`beamazon_fleetSim.setSpeed(60)`) alguns minutos, ou confira o XP em `beamazon_fleetManager.status()`.

1. `beamazon_company.buyUpgrade('bays')`: cobra $15.000 e o limite da frota sobe 1 (9).
2. `beamazon_fleetManager.buyTruck()`: cobra ~$18.000. Em `status()` o caminhão aparece como `parked, no driver`.
3. `beamazon_company.hireDriver()`: o caminhão começa a rodar. Depois de uma viagem, o lucro dele já vem sem o salário do motorista.
4. Salve, recarregue (Ctrl+L) e rode `status()`.

- **Esperado:** cada compra aparece como um lançamento no extrato. Depois do recarregamento, a melhoria, o motorista e o caminhão continuam lá. Nenhuma linha `E` no log.

### 19. Desgaste, quebra e revisão

No save com pelo menos 1 van na frota.

1. No console, force o desgaste de uma van para testar a quebra: `beamazon_fleetManager.getVans()[1].condition = 0.1`.
2. Acelere a frota no console: `beamazon_fleetSim.setSpeed(60)` e aguarde uma viagem terminar para ocorrer a quebra.
3. Observe no log (`status()`) e no celular o aviso de quebra e o tempo restante de reparo (`Broken down · N min` em vermelho).
4. No console ou pelo celular, revise a van: `beamazon_fleetManager.serviceVan(beamazon_fleetManager.getVans()[1].id)` ou toque em "Service" / "Service all" no app.
5. Salve o jogo e recarregue (Ctrl+L), depois confira com `beamazon_fleetManager.status()`.

- **Esperado:** os custos de reparo da quebra e de revisão aparecem como lançamentos no extrato bancário do RLS. A van quebrada fica parada sem realizar viagens até o reparo terminar. A condição e o tempo restante de reparo são preservados no save/recarregamento. Nenhuma linha `E` no log.

### 20. Filial das Dockyards

No save com a sede já fundada.

1. Para liberar a compra no teste: o nível 3 de empresa precisa de 1.500 XP de empresa. Conceda pelo console com `beamazon_fleetManager.getCompany().xpEarned = 1500`.
2. Como chegar ao local: entre em um veículo e toque no botão "Route" da filial Beamazon Dockyards na aba Empresa do celular, ou selecione o ponto no mapa grande (Spearleaf Logistics, armazéns do porto).
3. Caminhe até o ponto no local e compre a filial no cartão de atividade por $60.000.
4. Salve, recarregue (Ctrl+L) e confira com `beamazon_fleetManager.status()`.

- **Esperado:** $60.000 cobrados como lançamento no extrato bancário do RLS (`Beamazon: Beamazon Dockyards`), limite da frota sobe +4 vagas, e a filial comprada continua lá após o save e recarregamento. No local aparecem a mesa de escritório e o notebook ligado. Flavio: por favor avalie se a posição ficou ruim em jogo (atravessando parede, bloqueando a rua, etc.). Nenhuma linha `E` no log.

### 21. Melhorias por veículo

No save com pelo menos um veículo na frota.

1. No celular, na aba Frota, toque no botão "Upgrades" em um cartão de veículo e compre a melhoria Route Computer; ou pelo console: `beamazon_fleetManager.upgradeVehicle(beamazon_fleetManager.getVans()[1].id, 'routing')`.
2. Observe o nível atualizado no cartão (ex: `Lv 1/3`) e confira o extrato bancário do RLS.
3. Salve o jogo e recarregue (Ctrl+L), depois confira com `beamazon_fleetManager.status()`.
4. Confira o valor de venda do veículo no cartão ou via `beamazon_fleetManager.getSellValue(...)`.

- **Esperado:** o valor da melhoria é cobrado como um lançamento no extrato bancário do RLS (`Beamazon: <veículo> Route Computer 1`), o nível aparece no cartão da van, a melhoria e o valor gasto sobrevivem ao save e recarregamento, e o valor de venda do veículo aumenta em metade do valor gasto em melhorias. Nenhuma linha `E` no log.

### 22. Contratos de entrega

No save com pelo menos 1 veículo na frota.

1. Acelere a frota no console: `beamazon_fleetSim.setSpeed(60)`. Uma oferta de contrato surge em cerca de 1 min de jogo (3.600 s de frota), com aviso no log e notificação toast.
2. Abra o app Beamazon no celular: o cartão de oferta aparece no topo da aba Frota com cliente, viagens, prazo em horas, bônus, penalidade e tempo para expirar.
3. Toque em "Accept" para aceitar o contrato. O cartão passa a exibir o progresso das entregas, o tempo restante e o bônus.
4. Conclua as viagens com a frota trabalhando acelerada até atingir a meta. Em outro teste, deixe o tempo expirar para conferir a penalidade (com `setSpeed(60)` é rápido).
5. Salve o jogo e recarregue (Ctrl+L), depois confira o estado pelo celular e pelo console.

- **Esperado:** bônus pago como lançamento no extrato bancário do RLS (`Beamazon: contract with <cliente>`) e XP de empresa adicionado quando houver sede; penalidade cobrada no extrato quando o contrato for perdido (`Beamazon: missed contract with <cliente>`); o cartão mostra o progresso das viagens e o tempo restante; a linha "Contracts" reflete os bônus/penalidades na aba Finances; e o estado sobrevive ao save e recarregamento. Nenhuma linha `E` no log.

## Não crítico (acumula)

### 15. Celular: abas Frota / Empresa / Melhorias

Com a sede comprada, abra o app Beamazon.

- **Esperado:** aparecem três abas.
  - **Frota:** botões Van e Truck, e o caminhão sem motorista mostra `Parked · no driver`.
  - **Empresa:** nível e barra de XP, e os motoristas, contratados e demitidos com dois toques.
  - **Melhorias:** grupos People / HQ / Operations. Cada botão mostra preço e XP; o bloqueado diz `Needs …`.
- Comprar uma melhoria pelo celular cobra e atualiza a tela.

### 16. XP e nível da empresa

Com a frota rodando acelerada, observe o nível na aba Empresa.

- **Esperado:** o XP sobe com o lucro (1 XP a cada $100). Ao passar de 500 XP, aparece o aviso `Your company reached level 2.`

### 17. Celular: aba Finances

Abra o app Beamazon (com ou sem sede) e toque na aba Finances.

- **Esperado:** a aba Finances está sempre disponível na barra de abas (sem a sede, a barra mostra Fleet e Finances).
  - Sem entregas na frota, exibe o aviso `No deliveries yet.`.
  - Com entregas feitas, exibe o cartão `Last 24 h` com os totais (Revenue, Energy, Wear, Commission, Driver wages, Vehicles bought/sold, Net) e o gráfico de barras do lucro líquido de cada hora com o horário embaixo (ex: `14h`), barras positivas em verde e negativas em vermelho.

### 18. Mesa e notebook na sede

Vá até a sede no mapa (o ícone laranja).

- **Esperado:** ao lado do ponto aparecem uma mesa de escritório e um notebook ligado em cima dela (os mesmos das garagens do RLS). Se a mesa atravessar uma parede ou ficar virada para o lado errado, diga para que lado: o ajuste é uma linha (`desk.offset` e `desk.yaw` em `hq.lua`). Nenhuma linha `E` no log.

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
