# Estrutura de organização recomendada para Jellyfin

A melhor prática para organizar sua biblioteca do Jellyfin é criar uma estrutura de diretórios clara e consistente.

## Estrutura Sugerida

```
/mnt/media/jellyfin/media/
├── Filmes/
│   ├── Nome do Filme (Ano)/
│   │   └── nome_do_filme.mp4
├── Series/
│   ├── Nome da Série/
│   │   ├── Temporada 01/
│   │   │   └── nome_da_serie - s01e01 - nome_do_episodio.mp4
│   │   ├── Temporada 02/
│   │   │   └── ...
│   └── ...
└── Animes/
    ├── Nome do Anime/
    │   ├── Temporada 01/
    │   │   └── ...
    └── ...
```

### Detalhes

*   **Filmes**: Contém filmes organizados por seus respectivos nomes e anos de lançamento.
*   **Séries**: Organizadas por nome da série, temporadas e episódios.
*   **Animes**: Semelhante às séries, com nomes de animes e suas temporadas/episódios

## Importante

*   Esta estrutura facilita a catalogação e organização automática pelo Jellyfin.
*   Considere usar um software de renomeação em massa para padronizar os nomes dos arquivos.

## Considerações Finais

*   Adapte essa estrutura às suas necessidades e preferências.
*   Mantenha a organização consistente para evitar problemas de reconhecimento.