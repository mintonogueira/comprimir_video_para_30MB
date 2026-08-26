# Comprimir vídeo para 30 MB

Script Bash para reduzir um vídeo a um **tamanho máximo definido**, usando FFmpeg com codificação H.264 em duas passagens. O alvo padrão é **30 MB**, mas qualquer outro tamanho pode ser informado como segundo argumento.

O objetivo principal é resolver situações em que um vídeo precisa respeitar um limite rígido de tamanho para envio por mensageiros, formulários, sistemas web, e-mail ou outras plataformas.

## O que o script faz

O `reduzir-video.sh` automatiza todo o processo de cálculo e compressão. Em vez de usar apenas um nível de qualidade fixo, ele calcula o bitrate necessário a partir de três informações:

1. duração real do vídeo;
2. tamanho máximo solicitado;
3. bitrate reservado para o áudio.

A partir desses dados, o script determina quanto bitrate pode ser usado pelo vídeo para que o arquivo final permaneça dentro do limite.

### Principais recursos

- alvo padrão de **30 MB**;
- permite informar outros limites, como 20 MB, 50 MB ou 100 MB;
- trabalha corretamente com nomes de arquivos contendo espaços;
- detecta automaticamente a duração por meio do `ffprobe`;
- detecta se o arquivo possui faixa de áudio;
- calcula automaticamente o bitrate de vídeo adequado ao tamanho solicitado;
- utiliza **H.264/AVC (`libx264`)** para ampla compatibilidade;
- utiliza **AAC a 96 kbps** quando existe áudio;
- realiza compressão em **duas passagens (2-pass)** para melhorar a distribuição do bitrate e aproximar o tamanho final do alvo;
- utiliza o preset `slow`, priorizando eficiência de compressão;
- gera MP4 com `yuv420p`, aumentando a compatibilidade com navegadores, celulares, TVs e aplicativos;
- aplica `faststart`, movendo os metadados necessários para o início do MP4 e facilitando reprodução progressiva/streaming;
- mantém o arquivo original intacto;
- cria o arquivo convertido no mesmo diretório do vídeo de origem;
- cria e remove automaticamente os arquivos temporários usados pelo FFmpeg;
- verifica as dependências antes de iniciar;
- verifica se o arquivo informado existe;
- rejeita valores de tamanho inválidos;
- detecta quando o bitrate calculado seria baixo demais para uma conversão operacional;
- mede o tamanho real do resultado ao final e informa se ele ficou dentro do limite.

## Por que usar duas passagens

Quando a prioridade é atingir um **tamanho final específico**, codificação por CRF não é a estratégia mais previsível, pois CRF prioriza qualidade e deixa o tamanho variar conforme a complexidade das imagens.

Este script utiliza bitrate médio calculado e duas passagens:

### Primeira passagem

O FFmpeg analisa o vídeo inteiro e registra informações sobre sua complexidade. Nenhum vídeo final é produzido nessa etapa.

### Segunda passagem

O encoder utiliza as estatísticas coletadas anteriormente para distribuir melhor os bits entre cenas simples e complexas. Assim, cenas que exigem mais informação recebem mais bitrate e cenas simples recebem menos.

Isso torna o resultado mais adequado quando existe um limite rígido de tamanho.

## Margem de segurança

O script trabalha internamente com **97% do limite solicitado**.

Para um alvo de 30 MB, por exemplo, ele calcula o bitrate visando aproximadamente 29,1 MB antes do overhead final do container MP4.

Essa margem existe porque o tamanho de um MP4 não é formado apenas pelos fluxos de vídeo e áudio. O container também possui metadados, índices e estruturas internas, e pequenas variações podem ocorrer durante a muxagem.

Além disso, neste projeto **1 MB = 1.000.000 bytes**. Portanto, um limite de 30 MB corresponde a **30.000.000 bytes**, evitando a confusão com MiB (`1 MiB = 1.048.576 bytes`) em serviços que aplicam limites decimais.

## Dependências

O script requer:

- Bash;
- FFmpeg;
- ffprobe;
- awk;
- mktemp;
- wc;
- tr.

`ffprobe` normalmente é instalado junto com o pacote FFmpeg.

### Arch Linux

```bash
sudo pacman -S ffmpeg
```

### Debian / Ubuntu

```bash
sudo apt update
sudo apt install ffmpeg
```

### Fedora

```bash
sudo dnf install ffmpeg
```

## Instalação

Clone o repositório:

```bash
git clone https://github.com/mintonogueira/comprimir_video_para_30MB.git
cd comprimir_video_para_30MB
```

Dê permissão de execução ao script:

```bash
chmod +x reduzir-video.sh
```

## Uso

### Compressão para 30 MB

```bash
./reduzir-video.sh 'video.mp4'
```

Como 30 MB é o valor padrão, não é necessário informar o tamanho.

Também é possível especificá-lo explicitamente:

```bash
./reduzir-video.sh 'video.mp4' 30
```

### Outros tamanhos

Para 20 MB:

```bash
./reduzir-video.sh 'video.mp4' 20
```

Para 50 MB:

```bash
./reduzir-video.sh 'video.mp4' 50
```

Para 100 MB:

```bash
./reduzir-video.sh 'video.mp4' 100
```

Valores decimais também são aceitos:

```bash
./reduzir-video.sh 'video.mp4' 29.5
```

## Exemplo com arquivo do WhatsApp

```bash
./reduzir-video.sh 'WhatsApp Video 2026-08-26 at 14.52.55.mp4'
```

A saída será criada no mesmo diretório, com um nome semelhante a:

```text
WhatsApp Video 2026-08-26 at 14.52.55 - 30MB.mp4
```

## Como o bitrate é calculado

De forma simplificada, o script calcula primeiro o bitrate total disponível:

```text
bitrate_total = (tamanho_em_bytes × 8) / duração
```

Depois desconta o bitrate destinado ao áudio:

```text
bitrate_video = bitrate_total - bitrate_audio
```

Antes do cálculo, o tamanho máximo é multiplicado pela margem de segurança de 97%.

Quando existe áudio, são reservados 96 kbps para AAC. Se o arquivo não tiver áudio, todo o orçamento de bitrate disponível pode ser utilizado pelo vídeo.

## Formato de saída

O arquivo gerado utiliza:

| Elemento | Configuração |
|---|---|
| Container | MP4 |
| Vídeo | H.264 / AVC (`libx264`) |
| Método | 2-pass |
| Preset | `slow` |
| Pixel format | `yuv420p` |
| Áudio | AAC |
| Bitrate de áudio | 96 kbps |
| Fast Start | Ativado |
| Alvo padrão | 30 MB |

## Qualidade do resultado

Existe uma relação direta entre:

- duração;
- resolução;
- complexidade das imagens;
- quantidade de movimento;
- tamanho final permitido.

Dois vídeos de mesma duração e resolução podem apresentar resultados visuais diferentes porque cenas com muito movimento, ruído, granulação, água, folhas, multidões ou mudanças frequentes exigem mais bitrate.

Se um vídeo muito longo precisar caber em apenas 30 MB, o bitrate disponível poderá ficar baixo. Nesse cenário, reduzir a resolução ou a duração antes da compressão pode produzir qualidade visual significativamente melhor.

O script detecta situações em que o bitrate calculado cai abaixo do mínimo operacional configurado e interrompe o processo em vez de gerar silenciosamente um vídeo extremamente degradado.

## Arquivo original

O arquivo de entrada **não é modificado nem substituído**. O script cria uma nova versão no mesmo diretório.

Por exemplo:

```text
video.mp4
```

gera:

```text
video - 30MB.mp4
```

## Ajuda

```bash
./reduzir-video.sh --help
```

ou:

```bash
./reduzir-video.sh -h
```

## Observações

- o script espera pelo menos uma faixa de vídeo válida;
- apenas a primeira faixa de vídeo é utilizada;
- quando há áudio, a primeira faixa de áudio é utilizada;
- legendas e outras faixas auxiliares não são copiadas para o arquivo final;
- a resolução e o frame rate originais são mantidos pelo script;
- o resultado pode variar levemente devido às características do encoder e do container;
- a margem de segurança foi adotada justamente para reduzir o risco de ultrapassar o limite informado.

## Licença

Consulte o arquivo [`LICENSE`](LICENSE) presente neste repositório.
