# Beamazon (BeamNG.drive)

Mod para o modo carreira do BeamNG.drive: compre vans elétricas autônomas, coloque-as para fazer entregas sozinhas e gerencie a frota como uma empresa, cuidando de energia, desgaste, upgrades e vagas nos depósitos.

- **Jogo:** BeamNG.drive 0.40
- **Funciona com:** carreira vanilla; integração opcional com o [RLS Career Overhaul](https://github.com/RLS-Modding/rls_career_overhaul)
- **Status:** fase 0 (exploração da API da carreira)
- **Autores:** Flavio e Bernardo

## Como funciona

As vans não rodam fisicamente no mapa. Cada uma é simulada como dado, então uma frota de 50 vans não pesa no FPS. Cada entrega rende o valor que o jogo pagaria por ela, menos energia, desgaste, comissão e seguro. A empresa ganha XP, desbloqueia mais vagas e contratos melhores, e cada propriedade comprada libera vagas de frota.

Detalhes em [`docs/plano.md`](docs/plano.md).

## Desenvolvimento

```bash
# Ligar o mod ao jogo (uma vez por PC)
scripts/dev-link.sh
# Gerar o zip de release em dist/
scripts/pack.sh
```

O jogo carrega `mod/` direto pelo link `mods/unpacked/beamazon`. No jogo, `Ctrl+L` recarrega o Lua.

| Pasta | Conteúdo |
|---|---|
| `mod/` | O mod em si, espelhando a estrutura do jogo (só isto vai para o zip) |
| `docs/plano.md` | Ideia, economia, slots, arquitetura e roadmap |
| `docs/api-jogo.md` | Funções reais da carreira que o mod usa (mapeadas na fase 0) |
| `scripts/` | Link de desenvolvimento e empacotamento |
