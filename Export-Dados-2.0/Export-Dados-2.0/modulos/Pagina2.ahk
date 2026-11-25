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
    Send("^a")
    Aguardar(150)
    Send("^c")

    if !AguardarClipboard(1.5) {
        ; sem {Left} aqui — nada foi selecionado, entao nao ha o que desfazer
        ; (e {Left} sobre foco num botao pode pular pro elemento vizinho)
        RegistrarEvento("Obter quantidade resultados", "ERRO", "clipboard nao respondeu")
        return -1
    }

    textoPagina := A_Clipboard
    Send("{Left}")

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
    global delayCurto, delayMedio, caminhoDownload

    ; ---------- validação de quantidade ----------
    ; Classe RPC não usa o mínimo de 20 (os grupos de conta RPC —
    ; Prefeitura/FAS/Câmara — legitimamente retornam poucos resultados e
    ; variam bastante entre entidades, então até um mínimo reduzido ainda
    ; abortava ciclos válidos), mas AINDA aborta se a página realmente não
    ; tiver NENHUM resultado (qtd=0, "Sem informações para serem listadas."
    ; — ver ObterQuantidadeResultados) ou se não conseguir nem ler o texto
    ; da página (qtd=-1) — lista vazia continua sendo lista vazia, mesmo
    ; sem exigir um mínimo de 20. Detecta RPC pelo próprio prefixo do
    ; arquivo (sempre contém "_RPC_" nesse caso — ver InserirContas/
    ; AplicarConta) em vez de um flag global à parte, pra continuar valendo
    ; certinho mesmo depois de um reset (F3), já que "prefix" já sobrevive
    ; a isso via classe_atual.txt.
    ehClasseRPC := InStr(prefix, "_RPC_") ? true : false
    qtd := ObterQuantidadeResultados()

    if (ehClasseRPC && qtd <= 0) {
        motivo := (qtd == -1) ? "Texto de resultados nao encontrado"
                             : "Sem resultados: pagina reportou 'Sem informacoes para serem listadas'"

        FileAppend(dataTag . ";" . motivo . " | Etapa: validacao de quantidade na PAGINA2 (RPC)`n", logFile)
        RegistrarEvento("Validacao quantidade", "ABORTADO", motivo)
        SoundBeep(750, 300)
        TrayTip("Inconsistência Detectada!", dataTag . ": " . motivo, 16)

        VoltarParaPrimeiraPagina(dataTag, logFile)
        return false
    } else if (!ehClasseRPC && qtd < 20) {
        motivo := (qtd == -1) ? "Texto de resultados nao encontrado"
                             : "Inconsistencia: Apenas " . qtd . " resultado(s) encontrado(s) (minimo 20)"

        FileAppend(dataTag . ";" . motivo . " | Etapa: validacao de quantidade na PAGINA2`n", logFile)
        RegistrarEvento("Validacao quantidade", "ABORTADO", motivo)
        SoundBeep(750, 300)
        TrayTip("Inconsistência Detectada!", dataTag . ": " . motivo, 16)

        VoltarParaPrimeiraPagina(dataTag, logFile)
        return false
    }

    ; ---------- Localiza "Exportar em PDF" via Ctrl+F ----------
    ; Ctrl+F + 3 Tabs pra frente + Enter (sem Shift+Tab, sem tab extra) —
    ; é o mecanismo comprovadamente funcionando pra esse botão específico.
    Send("^f")
    Aguardar(250)
    Send("^a") ; seleciona TODO o texto da busca anterior — nao confia que ja venha pre-selecionado
    Aguardar(60)
    Send("{BackSpace}") ; apaga a selecao inteira, garantindo a caixa de busca vazia antes de digitar
    Aguardar(delayCurto)
    SendText("Exportar em PDF")
    Aguardar(250)
    Send("{Enter}")
    Aguardar(200)

    Loop 3 {
        Aguardar(delayCurto)
        Send("{Tab}")
    }
    Send("{Enter}")
    RegistrarEvento("Confirmar Exportar em PDF", "OK")
    Aguardar(delayMedio)

    ; ---------- Interação com Dropdown (formato do arquivo) ----------
    Send("{Tab}")
    Aguardar(delayCurto)
    Send("{Enter}")

    Loop 10 {
        Aguardar(30)
        Send("{Down}")
    }
    Aguardar(delayCurto)
    Send("{Enter}")
    RegistrarEvento("Selecionar formato CSV", "OK")

    ; ---------- SALVAR COMO ----------
    nomeDoArquivo := dataTag . "_" . prefix

    ; 20s (nao 5s) — a janela "Salvar como" as vezes demora bastante pra
    ; abrir (geracao do CSV, gravacao em disco de rede, etc.); 5s estava
    ; abortando ciclos que so precisavam de mais alguns segundos.
    ; AguardarJanelaAtiva (não WinWaitActive nativo) retorna assim que a
    ; janela aparece, entao isso nao deixa ciclos rapidos mais lentos — só
    ; dá mais margem pros lentos. Além disso, ao contrário do WinWaitActive
    ; nativo, checa VerificarControles() a cada ~100ms durante a espera —
    ; sem isso, apertar F2 enquanto o script esperava essa janela (até 20s
    ; inteiros!) não pausava nada até a espera acabar sozinha, mesmo com a
    ; interface já mostrando "Pausado" — bug real confirmado pelo usuário.
    if !AguardarJanelaAtiva("Salvar como", 20) {
        FileAppend(dataTag . ";ABORTADO - janela 'Salvar como' nao apareceu apos exportar | Etapa: pos-exportacao PDF`n", logFile)
        RegistrarEvento("Janela Salvar como", "ABORTADO", "nao apareceu apos exportar")
        SoundBeep(500, 300)
        VoltarParaPrimeiraPagina(dataTag, logFile)
        return false
    }
    RegistrarEvento("Janela Salvar como", "OK", "apareceu")
    Aguardar(delayMedio)

    Send("^l")
    Aguardar(200)
    SendText(caminhoDownload)
    Aguardar(delayCurto)
    Send("{Enter}")
    RegistrarEvento("Definir pasta destino", "OK", caminhoDownload)
    Aguardar(delayMedio)

    Loop 6 {
        Send("{Tab}")
        Aguardar(delayCurto)
    }
    Aguardar(delayCurto)

    ; FAPS/RPC: só INSERE no início (Home + digitar), preservando o resto
    ; do nome padrão que a página já sugere (ex.: "ConsultaEventos.csv") —
    ; nomeDoArquivo vira só um prefixo.
    ;
    ; e-Social: SUBSTITUI o nome inteiro (Ctrl+A + digitar) — o nome padrão
    ; que vem na caixa termina num código gerado pelo sistema que precisa
    ; ser removido (pedido explícito do usuário), não só prefixado. Em vez
    ; do código, escreve "Consulta Eventos" (com espaço, sem ".csv" — a
    ; extensão continua vindo sozinha do tipo de arquivo já selecionado no
    ; dropdown acima) na hora.
    if (ehESocial) {
        Send("^a")
        Aguardar(delayCurto)
        nomeDoArquivo := nomeDoArquivo . "Consulta Eventos"
        SendText(nomeDoArquivo)
    } else {
        Send("{Home}")
        Aguardar(delayCurto)
        SendText(nomeDoArquivo)
    }
    Aguardar(delayCurto)
    Send("{Enter}")
    RegistrarEvento("Salvar arquivo", "OK", nomeDoArquivo)
    Aguardar(delayMedio)

    return true
}
