; =====================================================================
; Pagina2.ahk
; Tudo que acontece na PÁGINA 2 (resultados): validar quantidade,
; exportar em PDF/CSV e salvar o arquivo. Portado do V2 sem mudança de
; comportamento.
; =====================================================================

; =========================================================================
; VERIFICA A QUANTIDADE DE RESULTADOS NA PÁGINA 2
; Retorna: >= 0 quantidade encontrada | -1 falha de leitura/texto não achado
; =========================================================================
ObterQuantidadeResultados() {
    global janelaAlvo

    if !WinActive(janelaAlvo) {
        WinActivate(janelaAlvo)
        AguardarJanelaAtiva(janelaAlvo, 2)
    }

    A_Clipboard := ""
    EnviarTecla("^a")
    Aguardar(150)
    EnviarTecla("^c")

    if !AguardarClipboard(1.5) {
        ; sem {Left} aqui — nada foi selecionado, entao nao ha o que desfazer
        ; (e {Left} sobre foco num botao pode pular pro elemento vizinho)
        RegistrarEvento("Obter quantidade resultados", "ERRO", "clipboard nao respondeu")
        return -1
    }

    textoPagina := A_Clipboard
    EnviarTecla("{Left}")

    ; A página mostra essa mensagem (em vez de "N resultado(s)
    ; encontrado(s)") quando a consulta realmente não retornou NENHUMA
    ; linha — precisa contar como qtd=0 de verdade, não como "não consegui
    ; ler o texto" (-1): sem esse caso separado, uma lista vazia de verdade
    ; passava batido pra classe RPC (que não usa mais o mínimo de 20/5, ver
    ; ValidarEExportarPagina2) e exportava um CSV vazio sem abortar.
    if InStr(textoPagina, "Sem informações para serem listadas") {
        RegistrarEvento("Obter quantidade resultados", "OK", "qtd=0 (pagina reportou 'Sem informacoes para serem listadas')")
        return 0
    }

    if RegExMatch(textoPagina, "i)(\d+)[\s\r\n]*resultado\(s\)[\s\r\n]*encontrado\(s\)", &match) {
        RegistrarEvento("Obter quantidade resultados", "OK", "qtd=" . match[1])
        return Integer(match[1])
    }

    RegistrarEvento("Obter quantidade resultados", "ERRO", "texto de resultados nao encontrado")
    return -1
}

; =========================================================================
; Valida a quantidade de resultados, exporta em CSV e salva o arquivo.
; Retorna true se tudo correu bem. Se falhar, já registra o motivo no log,
; soa o beep/TrayTip de aborto, volta pra página 1 e retorna false — quem
; chama (ProcessarCiclo) só precisa checar o retorno.
; =========================================================================
; ehESocial (opcional): muda só o mecanismo de preencher o nome do arquivo
; na janela "Salvar como" (ver mais abaixo) — pro e-Social, a caixa vem com
; um nome padrão terminado num código gerado pelo sistema que precisa ser
; REMOVIDO (não preservado como o FAPS faz); pro FAPS/RPC, comportamento
; inalterado.
ValidarEExportarPagina2(dataTag, prefix, logFile, ehESocial := false) {
    global delayCurto, delayMedio, caminhoDownload, g_Navegador, janelaAlvo

    ; ---------- validação de quantidade ----------
    ; Classe RPC não exige o mínimo de 20 (os grupos RPC — Prefeitura/FAS/
    ; Câmara — legitimamente retornam poucos resultados e variam bastante
    ; entre entidades), mas ainda aborta se a página não tiver NENHUM
    ; resultado (qtd=0) ou se não conseguir ler o texto (qtd=-1). Detecta
    ; RPC pelo próprio prefixo do arquivo (sempre contém "_RPC_" — ver
    ; InserirContas/AplicarConta), que sobrevive a um reset (F3) via
    ; classe_atual.txt.
    ehClasseRPC := InStr(prefix, "_RPC_") ? true : false
    qtd := ObterQuantidadeResultados()

    if (ehClasseRPC && qtd <= 0) {
        motivo := (qtd == -1) ? "Texto de resultados nao encontrado"
                             : "Sem resultados: pagina reportou 'Sem informacoes para serem listadas'"

        FileAppend(dataTag . ";" . motivo . " | Etapa: validacao de quantidade na PAGINA2 (RPC)`n", logFile)
        RegistrarEvento("Validacao quantidade", "ABORTADO", motivo)
        TrayTip("Inconsistência Detectada!", dataTag . ": " . motivo, 16)

        VoltarParaPrimeiraPagina(dataTag, logFile)
        return false
    } else if (!ehClasseRPC && qtd < 20) {
        motivo := (qtd == -1) ? "Texto de resultados nao encontrado"
                             : "Inconsistencia: Apenas " . qtd . " resultado(s) encontrado(s) (minimo 20)"

        FileAppend(dataTag . ";" . motivo . " | Etapa: validacao de quantidade na PAGINA2`n", logFile)
        RegistrarEvento("Validacao quantidade", "ABORTADO", motivo)
        TrayTip("Inconsistência Detectada!", dataTag . ": " . motivo, 16)

        VoltarParaPrimeiraPagina(dataTag, logFile)
        return false
    }

    ; ---------- Localiza "Exportar em PDF" via Ctrl+F ----------
    ; Ctrl+F + Enter (confirma o match) — igual nos dois navegadores. Dali
    ; em diante, o caminho até o dropdown de formato diverge (mecanismo
    ; próprio, não usa FecharBuscaCtrlF):
    ;   - Chrome: 3 Tabs pra frente + Enter, depois mais 1 Tab + Enter pra
    ;     abrir o dropdown de formato antes das setas.
    ;   - Firefox: 1 único Shift+Tab, direto depois do Enter que confirma o
    ;     match, já leva pro dropdown de formato pronto pra usar as setas —
    ;     sem precisar fechar a busca nem do Tab+Enter extra do Chrome.
    EnviarTecla("^f")
    Aguardar(250)
    EnviarTecla("^a") ; seleciona TODO o texto da busca anterior — nao confia que ja venha pre-selecionado
    Aguardar(60)
    EnviarTecla("{BackSpace}") ; apaga a selecao inteira, garantindo a caixa de busca vazia antes de digitar
    Aguardar(delayCurto)
    EnviarTexto("Exportar em PDF")
    Aguardar(250)
    EnviarTecla("{Enter}")
    Aguardar(200)
    tickAntesSetas := A_TickCount ; timer do diagnostico — ver log "Tempo ate Enter final" abaixo

    if (g_Navegador = "FIREFOX") {
        EnviarTecla("+{Tab}")
        Aguardar(delayCurto)
        EnviarTecla("{Enter}")
        RegistrarEvento("Confirmar Exportar em PDF", "OK")
        Aguardar(delayMedio)
    } else {
        Loop 3 {
            Aguardar(delayCurto)
            EnviarTecla("{Tab}")
        }
        EnviarTecla("{Enter}")
        RegistrarEvento("Confirmar Exportar em PDF", "OK")
        Aguardar(delayMedio)

        ; ---------- Interação com Dropdown (formato do arquivo) ----------
        EnviarTecla("{Tab}")
        Aguardar(delayCurto)
        EnviarTecla("{Enter}")
    }

    ; Cada seta é registrada individualmente (em vez de só logar o total no
    ; final) pra saber, se travar/for interrompido no meio, até qual delas
    ; chegou de fato. RegistrarEvento so grava no log (nao manda tecla
    ; nenhuma na pagina) — nao interfere no dropdown.
    Loop 10 {
        Aguardar(30)
        EnviarTecla("{Down}")
        RegistrarEvento("Seta para baixo " . A_Index . "/10", "OK")
    }

    Aguardar(delayCurto)
    EnviarTecla("{Enter}")
    RegistrarEvento("Selecionar formato CSV", "OK", "tempo desde Enter que confirmou match ate aqui=" . (A_TickCount - tickAntesSetas) . "ms")

    ; ---------- DIAGNÓSTICO: captura o estado DEPOIS do Enter final ----------
    trechoAposEnter := TrechoDoCampo(CapturarResumoPagina(200000), "Exportar", 1500)
    RegistrarEvento("Estado apos Enter final (formato)", "OK", trechoAposEnter)

    ; ---------- SALVAR COMO ----------
    nomeDoArquivo := dataTag . "_" . prefix

    ; (versão anterior, mantida comentada — detectava pelo TÍTULO da janela
    ; nativa "Salvar como" via AguardarJanelaAtiva; substituída pela leitura
    ; da URL abaixo (AguardarSairDoSite/Utilitarios.ahk), que não depende do
    ; título/idioma da janela: sabemos os domínios de todos os sites (ver
    ; DetectarEntidadeURL), então quando o foco sai de todos eles é sinal de
    ; que "Salvar como" tomou o foco.)
    ; if !AguardarJanelaAtiva("Salvar como", 20) {
    ;     FileAppend(dataTag . ";ABORTADO - janela 'Salvar como' nao apareceu apos exportar | Etapa: pos-exportacao PDF`n", logFile)
    ;     RegistrarEvento("Janela Salvar como", "ABORTADO", "nao apareceu apos exportar")
    ;     VoltarParaPrimeiraPagina(dataTag, logFile)
    ;     return false
    ; }
    ; RegistrarEvento("Janela Salvar como", "OK", "apareceu")

    ; 20s (não 5s) — a janela "Salvar como" às vezes demora bastante pra
    ; abrir (geração do CSV, gravação em disco de rede, etc.). Continua
    ; checando F2/F3/Esc durante a espera (AguardarSairDoSite usa
    ; VerificarControles a cada 100ms, igual o mecanismo antigo).
    if !AguardarSairDoSite(20) {
        FileAppend(dataTag . ";ABORTADO - janela 'Salvar como' nao apareceu apos exportar | Etapa: pos-exportacao PDF`n", logFile)
        RegistrarEvento("Janela Salvar como", "ABORTADO", "nao apareceu apos exportar (URL continuou no site)")
        VoltarParaPrimeiraPagina(dataTag, logFile)
        return false
    }
    RegistrarEvento("Janela Salvar como", "OK", "saiu da URL do site (Salvar como presumido em foco)")
    ; Firefox nao cria um processo separado pra essa janela (Chrome cria) —
    ; ela fica mais integrada ao processo do proprio Firefox, o que atrasa
    ; ela ficar de fato pronta pra receber teclado mesmo depois do Windows
    ; já reportar a janela como ativa. delayMedio (800ms) não bastava mais
    ; aqui — aumentado pra dar mais tempo de assentamento.
    Aguardar(1500)

    ; A janela "Salvar como" abre com o foco já na barra de caminhos — por
    ; isso o caminho é definido PRIMEIRO (Ctrl+L de novo aqui é só pra
    ; garantir o foco/seleção, idempotente), e só depois o nome do arquivo.
    EnviarTecla("^l")
    Aguardar(200)
    EnviarTexto(caminhoDownload)
    Aguardar(delayCurto)
    EnviarTecla("{Enter}")
    RegistrarEvento("Definir pasta destino", "OK", caminhoDownload)
    Aguardar(delayMedio)

    ; (versões anteriores, mantidas comentadas — contavam Tabs/Shift+Tabs da
    ; barra de caminhos até a caixa "Nome do arquivo"; a ordem de tabulação
    ; real não é confiável o bastante em nenhum dos dois navegadores)
    ; Loop 6 {
    ;     EnviarTecla("{Tab}")
    ;     Aguardar(delayCurto)
    ; }
    ; Aguardar(delayCurto)
    ; Loop 12 {
    ;     EnviarTecla("+{Tab}")
    ;     Aguardar(250)
    ; }
    ; Aguardar(250)

    ; Separado por navegador de propósito (mesmo fazendo a mesma coisa hoje)
    ; pra facilitar divergir depois se um dos dois precisar de outro
    ; mecanismo. "N" é o mnemônico sublinhado de "Nome do arquivo:" na
    ; janela "Salvar como" — assumido válido nos dois até prova em
    ; contrário (não confirmado ao vivo no Chrome ainda).
    if (g_Navegador = "FIREFOX") {
        EnviarTecla("{Tab}")
        Aguardar(250)
        EnviarTecla("!n")
        Aguardar(250)
    } else {
        EnviarTecla("{Tab}")
        Aguardar(250)
        EnviarTecla("!n")
        Aguardar(250)
    }

    ; ---------- TRAVA DE SEGURANÇA: confirma que o foco realmente chegou
    ; na caixa "Nome do arquivo" antes de digitar/salvar às cegas. O nome
    ; sugerido pelo sistema sempre começa com "Consulta Eventos" (ex.:
    ; "Consulta Eventos_6585077.csv") — se o texto capturado não contém
    ; isso, os 6 Shift+Tab não pousaram onde deveriam (ex.: na lista de
    ; arquivos) e digitar/Enter dali seria às cegas. Pausa em vez de
    ; seguir, e reavalia de novo ao retomar (F1) — cobre tanto o usuário
    ; corrigindo o foco manualmente quanto um novo estado da janela. ----------
    Loop {
        A_Clipboard := ""
        EnviarTecla("^a")
        Aguardar(30)
        EnviarTecla("^c")
        nomeAtual := AguardarClipboard(1) ? A_Clipboard : ""
        if InStr(nomeAtual, "Consulta Eventos")
            break
        TrayTip("Pausado", "Caminho errado", 3)
        DefinirPausado(true)
        VerificarControles() ; bloqueia aqui ate F1 retomar
    }

    ; FAPS/RPC: só INSERE no início (Home + digitar), preservando o resto
    ; do nome padrão que a página já sugere (ex.: "ConsultaEventos.csv") —
    ; nomeDoArquivo vira só um prefixo.
    ;
    ; e-Social: SUBSTITUI o nome inteiro (Ctrl+A + digitar) — o nome padrão
    ; que vem na caixa termina num código gerado pelo sistema que precisa
    ; ser removido, não só prefixado. Escreve "Consulta Eventos" (com
    ; espaço, sem ".csv" — a extensão já vem do tipo de arquivo selecionado
    ; no dropdown acima) no lugar do código.
    if (ehESocial) {
        EnviarTecla("^a")
        Aguardar(delayCurto)
        nomeDoArquivo := nomeDoArquivo . "Consulta Eventos"
        EnviarTexto(nomeDoArquivo)
    } else {
        EnviarTecla("{Home}")
        Aguardar(delayCurto)
        EnviarTexto(nomeDoArquivo)
    }
    Aguardar(delayCurto)
    EnviarTecla("{Enter}")
    RegistrarEvento("Salvar arquivo", "OK", nomeDoArquivo)
    Aguardar(delayMedio)

    return true
}
