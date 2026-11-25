; =====================================================================
; Utilitarios.ahk
; Funcoes genericas/compartilhadas, usadas por mais de um modulo (ou que
; nao pertencem especificamente a uma pagina): deteccao de pagina, espera,
; log, controles de pausa/reset, localizacao via Ctrl+F, captura de texto
; da tela, e pequenos helpers de string/data. Portado do V2 sem mudanca de
; comportamento.
; =====================================================================

; =========================================================================
; DETECÇÃO DE PÁGINA — em vez de confiar em sleeps fixos, lê o conteúdo
; real da tela (via seleção + cópia) e classifica em qual página estamos.
; Retorna: "PAGINA1", "PAGINA2", "CARREGANDO", "SEM_LEITURA" ou "DESCONHECIDA"
; =========================================================================
DetectarPagina() {
    global janelaAlvo

    if !WinActive(janelaAlvo) {
        WinActivate(janelaAlvo)
        AguardarJanelaAtiva(janelaAlvo, 1)
    }

    A_Clipboard := ""
    Send("^a")
    Aguardar(100)
    Send("^c")

    if !AguardarClipboard(1.5) {
        ; NAO envia {Left} aqui: se o Ctrl+A nao selecionou nada (ex.: foco
        ; num BOTAO, nao num campo de texto/corpo da pagina), nao ha o que
        ; desfazer — e {Left} nesse caso pode mover o foco para o elemento
        ; VIZINHO (ex.: de "Executar" para "Limpar"), quebrando o proximo clique.
        return "SEM_LEITURA"
    }

    texto := A_Clipboard
    Send("{Left}") ; desfaz a seleção para não atrapalhar o próximo passo (só quando algo foi de fato selecionado/copiado)

    ; PAGINA2 tem DUAS variações de texto possíveis: com resultados mostra
    ; "N resultado(s) encontrado(s)", mas com a lista VAZIA essa frase nem
    ; aparece — a página mostra "Sem informações para serem listadas." no
    ; lugar. Sem checar essa segunda variação, uma exportação vazia fazia
    ; DetectarPagina() nunca reconhecer PAGINA2 (caía sempre em
    ; "DESCONHECIDA"), o que travava o retry de "Voltar" — o código só
    ; reenvia Enter às cegas quando a página está num estado CONHECIDO e
    ; seguro (ver VoltarParaPrimeiraPagina/PreencherEExecutarPagina1).
    if InStr(texto, "resultado(s) encontrado(s)")
        return "PAGINA2"
    if InStr(texto, "Sem informações para serem listadas")
        return "PAGINA2"

    ; CARREGANDO: enquanto a consulta processa no servidor depois de clicar
    ; "Executar", a tela ainda mostra o formulário da Página 1 inteiro (com
    ; "Referência" e tudo mais) — SEM esse estado, essa tela seria
    ; classificada como PAGINA1 comum, e o script desistia por timeout fixo
    ; (~9,6s) mesmo com a consulta genuinamente ainda rodando no servidor
    ; (confirmado pelo usuário comparando uma captura normal com uma
    ; capturada durante o carregamento). O sinal encontrado: o texto
    ; "Executar" aparece DUAS vezes durante o carregamento (a segunda,
    ; extra, logo depois de "Limpar" no final do formulário) — só UMA vez
    ; fora desse estado. AguardarPagina trata CARREGANDO como "ainda
    ; progredindo, não conta pro timeout normal" (só um teto bem mais
    ; generoso, pra não esperar pra sempre se travar de verdade nesse
    ; estado).
    if (StrSplit(texto, "Executar").Length - 1 >= 2)
        return "CARREGANDO"

    if InStr(texto, "Referência")
        return "PAGINA1"

    return "DESCONHECIDA"
}

; =========================================================================
; VERIFICA CONTROLES (Esc / F2 / F3) por ESTADO FÍSICO da tecla
; (GetKeyState), em vez de depender só dos hotkeys do AHK.
; Motivo: com o script mandando Send()/SendText() quase sem parar durante
; os ciclos, o hook de teclado que detecta hotkeys pode nao conseguir
; reagir a tempo a uma tecla fisica real — daí F2/F3 "não fazerem nada"
; enquanto um ciclo está rodando. Checar o estado da tecla diretamente
; aqui, chamado com frequência (RegistrarEvento, AguardarPagina), não
; depende desse mecanismo e funciona mesmo com o script ocupado.
; =========================================================================
VerificarControles() {
    global g_Pausado

    if GetKeyState("Esc", "P")
        ExitApp()

    if GetKeyState("F3", "P") {
        while GetKeyState("F3", "P") ; espera soltar
            Sleep(30)
        ResetarScript()
    }

    if GetKeyState("F2", "P") {
        while GetKeyState("F2", "P") ; espera soltar
            Sleep(30)
        AlternarPausa() ; em Interface.ahk — mantém o botão "Pausar/Retomar" sincronizado
    }

    ; Enquanto pausado, o script fica só dormindo aqui (sem Send/SendText
    ; nenhum) — bem diferente do resto do ciclo, que é o cenário que
    ; justifica a checagem manual acima. Nesse estado o hook de hotkeys
    ; normal (F3:: no arquivo principal) já responde sem problema. Ainda
    ; assim, F3 também é checado manualmente aqui (igual Esc/F2) por
    ; consistência com o restante da função — nao ha motivo pra Reset ser
    ; o único controle que depende só do hook enquanto pausado.
    while (g_Pausado) {
        Sleep(150)
        if GetKeyState("Esc", "P")
            ExitApp()
        if GetKeyState("F3", "P") {
            while GetKeyState("F3", "P")
                Sleep(30)
            ResetarScript()
        }
        if GetKeyState("F2", "P") {
            while GetKeyState("F2", "P")
                Sleep(30)
            AlternarPausa()
        }
    }
}

; Substituto de Sleep() usado em TODO o código de automação (Send/SendText)
; — depois de esperar, chama VerificarControles() na hora, transformando
; cada espera num checkpoint de pausa/reset/aborto.
;
; Sem isso, apertar Pausar/Resetar/Esc só surtia efeito na próxima vez que
; RegistrarEvento ou AguardarPagina rodassem (os únicos lugares que já
; chamavam VerificarControles) — e entre uma chamada e outra, uma sequência
; inteira de Send/SendText/Sleep podia rodar sem checar nada, fazendo o
; script continuar mandando teclas por vários segundos depois de apertado
; Pausar, em vez de parar na hora.
;
; NÃO usar Aguardar() dentro de VerificarControles() (acima) nem no loop de
; polling de AguardarPagina (mais abaixo, que já chama VerificarControles()
; manualmente a cada iteração) — geraria recursão ou checagem duplicada.
Aguardar(ms) {
    Sleep(ms)
    VerificarControles()
}

; =========================================================================
; Espera (com polling, não sleep cego) até a página esperada aparecer.
; paginaDetectada (saída por referência) guarda o último valor lido —
; usado para compor a mensagem de erro no log em caso de timeout.
; =========================================================================
; intervaloChecagemMs: de quanto em quanto tempo DetectarPagina() (Ctrl+A/
; Ctrl+C) roda de novo. Padrão 400ms — F2/F3/Esc continuam checados a cada
; 100ms dentro desse intervalo de qualquer forma (via VerificarControles).
; Passar 100 aqui deixa a PRÓPRIA detecção de página (não só a pausa) mais
; responsiva, à custa de rodar o Ctrl+A/Ctrl+C com mais frequência — usado
; especificamente na espera por PAGINA2 depois de clicar "Executar" (ver
; PreencherEExecutarPagina1), pra perceber o fim do carregamento o mais
; rápido possível em vez de só a cada ~400ms.
AguardarPagina(paginaEsperada, timeoutSegundos, &paginaDetectada, intervaloChecagemMs := 400) {
    global TIMEOUT_MAX_CARREGANDO_SEGUNDOS
    inicio := A_TickCount
    inicioAbsoluto := A_TickCount
    Loop {
        VerificarControles()
        paginaDetectada := DetectarPagina()
        if (paginaDetectada = paginaEsperada) {
            RegistrarEvento("Aguardar " . paginaEsperada, "OK", "esperou " . (A_TickCount - inicioAbsoluto) . "ms")
            return true
        }

        ; Enquanto a página estiver "CARREGANDO" (consulta ainda processando
        ; no servidor — ver DetectarPagina), o timeout normal (curto,
        ; timeoutSegundos) é resetado a cada checagem: não faz sentido
        ; desistir só porque a consulta demorou mais que o esperado pra
        ; concluir, se ela visivelmente ainda está em andamento. Um teto
        ; bem mais generoso (TIMEOUT_MAX_CARREGANDO_SEGUNDOS) evita esperar
        ; pra sempre caso a tela realmente trave nesse estado.
        if (paginaDetectada = "CARREGANDO") {
            inicio := A_TickCount
            if ((A_TickCount - inicioAbsoluto) / 1000 > TIMEOUT_MAX_CARREGANDO_SEGUNDOS) {
                RegistrarEvento("Aguardar " . paginaEsperada, "ERRO", "TIMEOUT (travado em CARREGANDO) apos " . (A_TickCount - inicioAbsoluto) . "ms")
                return false
            }
        } else if ((A_TickCount - inicio) / 1000 > timeoutSegundos) {
            RegistrarEvento("Aguardar " . paginaEsperada, "ERRO", "TIMEOUT apos " . (A_TickCount - inicio) . "ms, ultima pagina detectada='" . paginaDetectada . "'")
            return false
        }
        ; Sleep em pedaços de 100ms (F2/F3/Esc sempre checados nessa
        ; granularidade), repetidos até completar intervaloChecagemMs —
        ; controla de quanto em quanto tempo o PRÓPRIO DetectarPagina()
        ; roda de novo (ver comentário no topo da função).
        Loop Max(1, Round(intervaloChecagemMs / 100)) {
            VerificarControles()
            Sleep(100)
        }
    }
}

; =========================================================================
; Substituto "pausável" de WinWaitActive() nativo — espera em pedaços
; pequenos (checando VerificarControles a cada ~100ms) em vez de bloquear
; o script inteiro até a janela ficar ativa ou o timeout estourar.
;
; BUG corrigido: WinWaitActive() nativo NÃO dá nenhuma chance do script
; checar F2/F3/Esc durante a espera — com timeouts de até 20s (ver
; ValidarEExportarPagina2, esperando a janela "Salvar como"), apertar F2
; nesse meio tempo não pausava nada até a espera terminar sozinha,
; mesmo com o botão/status já mostrando "Pausado" na interface
; (DefinirPausado só mexe na interface — quem realmente para a execução é
; VerificarControles(), então qualquer wait bloqueante sem esse checkpoint
; é um buraco na pausa). Confirmado pelo usuário como bug real. Retorna
; true/false igual WinWaitActive().
AguardarJanelaAtiva(criterio, timeoutSegundos) {
    inicio := A_TickCount
    Loop {
        VerificarControles()
        if WinActive(criterio)
            return true
        if ((A_TickCount - inicio) / 1000 > timeoutSegundos)
            return false
        Sleep(100)
    }
}

; Mesma ideia de AguardarJanelaAtiva, mas pra ClipWait() nativo (usado em
; CapturarResumoPagina/ObterQuantidadeResultados) — mesmo bug, mesmo
; motivo, mesma correção: polling em pedaços checando VerificarControles
; em vez de bloquear cego. Assume que o chamador já limpou A_Clipboard
; antes de disparar o Ctrl+C (padrão já usado em todo o código). Retorna
; true/false igual ClipWait().
AguardarClipboard(timeoutSegundos) {
    inicio := A_TickCount
    Loop {
        VerificarControles()
        if (A_Clipboard != "")
            return true
        if ((A_TickCount - inicio) / 1000 > timeoutSegundos)
            return false
        Sleep(100)
    }
}

; =========================================================================
; REGISTRA UM EVENTO no log de ações (log_acoes.csv), com o
; tempo decorrido (ms) desde o ÚLTIMO evento registrado — assim cada linha
; mostra quanto tempo aquela ação específica levou. Se ultrapassar
; LIMITE_ACAO_LENTA_MS, marca Lento=SIM e avisa via TrayTip (sem travar
; o fluxo nem soar o beep de erro).
; status sugerido: "OK", "AVISO", "ERRO", "ABORTADO"
; =========================================================================
RegistrarEvento(etapa, status := "OK", detalhes := "") {
    global g_CicloAtual, g_UltimoTickAcao, logAcoes, LIMITE_ACAO_LENTA_MS

    agora   := A_TickCount
    duracao := (g_UltimoTickAcao = 0) ? 0 : (agora - g_UltimoTickAcao)
    g_UltimoTickAcao := agora

    lento := (duracao > LIMITE_ACAO_LENTA_MS) ? "SIM" : "NAO"
    timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")

    linha := timestamp . ";" . g_CicloAtual . ";" . etapa . ";" . duracao . ";"
           . LIMITE_ACAO_LENTA_MS . ";" . lento . ";" . status . ";" . detalhes . "`n"

    ; O arquivo de log pode estar momentaneamente travado (ex.: outro
    ; programa lendo ele ao mesmo tempo) — tenta algumas vezes em vez de
    ; deixar isso derrubar o script inteiro por causa de UMA linha de log.
    ; VerificarControles() antes de cada retry (não só Sleep cego): sem
    ; isso, até 5x100ms=500ms passavam sem checar F2/F3/Esc.
    Loop 5 {
        try {
            FileAppend(linha, logAcoes)
            break
        } catch {
            VerificarControles()
            Sleep(100)
        }
    }

    ; Algumas etapas são sabidamente lentas por motivo já conhecido/aceito,
    ; então a demora não é sinal de nada errado — vira só ruído repetir um
    ; TrayTip pra cada uma, enterrando os avisos que realmente importam.
    ; Ainda ficam marcadas "lento=SIM" no CSV, só não disparam o TrayTip:
    ;   - "Janela Salvar como": o SO demora mesmo pra abrir o diálogo (já
    ;     levado em conta no timeout do WinWaitActive).
    ;   - "Limpar caixa X" / "Inserir X" (Conta/Tipo Folha, ver
    ;     InserirCampoMultiSelect em Pagina1.ahk): envolvem capturar até
    ;     200000 chars da página via Ctrl+A/Ctrl+C (às vezes 2x seguidas)
    ;     só pra registro/diagnóstico — não bloqueiam mais o fluxo nem
    ;     indicam falha, então a demora sozinha não justifica alarme.
    etapaLentaConhecida := (etapa = "Janela Salvar como")
        || InStr(etapa, "Limpar caixa ") = 1
        || InStr(etapa, "Inserir ") = 1
    if (lento = "SIM" && !etapaLentaConhecida)
        TrayTip("Ação lenta detectada", g_CicloAtual . " - " . etapa . " levou " . duracao . "ms", 1)

    ; Chamado no FIM (não no início) — assim uma pausa acionada aqui não
    ; entra na duracao_ms do evento que acabou de ser registrado.
    VerificarControles()
}

; =========================================================================
; Localiza um texto via Ctrl+F e, a partir dali, dá N Tabs.
; Ctrl+F + Enter + 1 Shift+Tab fecha a busca do Chrome e deixa o foco EM
; CIMA do elemento encontrado — usado para "Referência"/"Executar"/"Voltar"
; (pagina 1). "Exportar em PDF" (pagina 2) NAO usa esta função — usa Ctrl+F
; + 3 Tabs direto no modulo da Pagina2, pois o Shift+Tab se mostrou flaky ali.
; ativarComEnter: alguns alvos (ex.: o rótulo "Referência") precisam de um
; Enter extra logo após o fechamento da busca para "ativar"/selecionar o
; elemento encontrado antes de dar os Tabs seguintes — passe true nesses casos.
; tabsExtras é para quando o alvo é um campo de escrita e é preciso avançar
; mais alguns Tabs além do elemento encontrado para chegar no input real
; (para botões, tabsExtras deve ser 0 — o elemento já está focado).
; =========================================================================
LocalizarEFocar(textoAlvo, tabsExtras := 0, ativarComEnter := false) {
    global janelaAlvo, delayCurto

    if !WinActive(janelaAlvo) {
        WinActivate(janelaAlvo)
        AguardarJanelaAtiva(janelaAlvo, 2)
    }

    Send("^f")
    Aguardar(150)
    Send("^a") ; seleciona TODO o texto da busca anterior — nao confia que ja venha pre-selecionado
    Aguardar(60)
    Send("{BackSpace}") ; apaga a selecao inteira, garantindo a caixa de busca vazia antes de digitar
    Aguardar(delayCurto)
    SendText(textoAlvo)
    Aguardar(150)
    Send("{Enter}")
    Aguardar(120)

    Aguardar(delayCurto)
    Send("+{Tab}")

    if (ativarComEnter) {
        Aguardar(delayCurto)
        Send("{Enter}")
    }

    Loop tabsExtras {
        Aguardar(delayCurto)
        Send("{Tab}")
    }

    RegistrarEvento("Localizar: " . textoAlvo, "OK", "tabsExtras=" . tabsExtras . " ativarComEnter=" . ativarComEnter)
}

; =========================================================================
; DIAGNÓSTICO: captura um resumo do texto atual da tela (via seleção+cópia)
; e devolve já sanitizado para caber numa única célula do CSV (sem quebras
; de linha nem ';'). Usado para ver O QUE está na tela num instante
; específico, sem esperar o timeout inteiro de AguardarPagina.
; =========================================================================
CapturarResumoPagina(maxChars := 300) {
    global janelaAlvo

    if !WinActive(janelaAlvo) {
        WinActivate(janelaAlvo)
        AguardarJanelaAtiva(janelaAlvo, 1)
    }

    A_Clipboard := ""
    Send("^a")
    Aguardar(30) ; minimo pra selecao registrar antes do copy — reduzido pra
                 ; encurtar o tempo que a pagina inteira fica destacada na tela
    Send("^c")

    if !AguardarClipboard(1) {
        ; sem {Left} aqui — nada foi selecionado, entao nao ha o que desfazer
        return "[SEM_LEITURA]"
    }

    ; desfaz a selecao IMEDIATAMENTE (antes de processar/truncar o texto),
    ; pra minimizar o tempo que a pagina fica com a cor de selecao inteira
    Send("{Left}")
    texto := A_Clipboard

    texto := StrReplace(texto, "`r`n", " | ")
    texto := StrReplace(texto, "`n", " | ")
    texto := StrReplace(texto, ";", ",")

    if (StrLen(texto) > maxChars)
        texto := SubStr(texto, 1, maxChars) . "...(truncado, total=" . StrLen(texto) . " chars)"

    return texto
}

; =========================================================================
; Volta para a página 1 usando a mesma técnica de busca (já funcionava
; nesta parte) e agora confirma via DetectarPagina() em vez de sleep fixo.
; O botão "Voltar" fica na Página 2, mas essa função é chamada de vários
; lugares (recuperação de estado, fim de ciclo) — por isso fica aqui como
; utilitário compartilhado, e não só dentro do módulo da Página 2.
; =========================================================================
VoltarParaPrimeiraPagina(dataTag, logFile) {
    global delayCurto, delayMedio, janelaAlvo
    global TABS_APOS_VOLTAR

    if !WinActive(janelaAlvo) {
        WinActivate(janelaAlvo)
        AguardarJanelaAtiva(janelaAlvo, 2)
    }

    LocalizarEFocar("Voltar", TABS_APOS_VOLTAR)

    ; Mesma tecnica usada no Executar: um Tab pra frente e um Shift+Tab de
    ; volta refaz o "pouso" no botao por navegacao normal, sem pegada da
    ; barra de busca — ajuda o clique a "pegar" de forma mais confiavel.
    Aguardar(60)
    Send("{Tab}")
    Aguardar(60)
    Send("+{Tab}")

    ; Faltava aqui o delay de assentamento que o Executar já tem (lá é
    ; Sleep(150) antes do primeiro Enter) — sem ele, o botão "Voltar"
    ; ficava com o foco visualmente certo mas o Enter seguinte não
    ; "pegava" (observado especificamente com a tabela de resultados
    ; vazia — "Sem informações para serem listadas"). delayMedio (800ms)
    ; em vez de um valor menor porque o caso que falhava é justamente
    ; esse: precisa de mais tempo que o suficiente pro Executar.
    Aguardar(delayMedio)

    ; O Enter unico com pausa de 700ms foi testado e NAO funcionou. Voltando
    ; pro retry comprovado: reenvia o Enter se a pagina nao mudar em 800ms.
    chegouPagina1 := false
    Loop 2 {
        Send("{Enter}")
        RegistrarEvento("Confirmar Voltar (tentativa " . A_Index . ")", "OK")

        if AguardarPagina("PAGINA1", 0.8, &pagAtual) {
            chegouPagina1 := true
            break
        }
        RegistrarEvento("Voltar sem efeito ainda", "AVISO", "tentativa=" . A_Index . " pagina='" . pagAtual . "'")

        if (pagAtual != "PAGINA2" && pagAtual != "SEM_LEITURA") {
            RegistrarEvento("Voltar: parando retries", "AVISO", "pagina inesperada='" . pagAtual . "', nao vou reenviar Enter as cegas")
            break
        }
    }

    if !chegouPagina1 && !AguardarPagina("PAGINA1", 8, &pagAtual) {
        FileAppend(dataTag . ";ABORTADO - esperava PAGINA1 apos Voltar, detectado '" . pagAtual . "' | Etapa: pos-Voltar (transicao pagina2 -> pagina1)`n", logFile)
        SoundBeep(500, 300)
        TrayTip("Ciclo abortado", dataTag . ": não retornou à página 1 (" . pagAtual . ")", 16)
    }
}

; ===================== CALCULA O ÚLTIMO DIA DO MÊS ======================
UltimoDiaDoMes(ano, mes) {
    if (mes = 12) {
        proxMes := 1
        proxAno := ano + 1
    } else {
        proxMes := mes + 1
        proxAno := ano
    }
    primeiroDoProximo := Format("{:04}{:02}01000000", proxAno, proxMes)
    ultimoDiaYYYYMMDD  := DateAdd(primeiroDoProximo, -1, "Days")
    return FormatTime(ultimoDiaYYYYMMDD, "dd/MM/yyyy")
}

; Remove acentos comuns do português (maiúsculas e minúsculas), pra comparar/
; montar texto sem depender de como o usuário digitou (ex.: "Câmara" ->
; "Camara"). Usado por DetectarGrupoRPC, abaixo, pra reconhecer a Entidade
; digitada na interface independente de acento/caixa.
RemoverAcentos(texto) {
    static mapa := Map(
        "á","a","à","a","â","a","ã","a","ä","a",
        "é","e","è","e","ê","e","ë","e",
        "í","i","ì","i","î","i","ï","i",
        "ó","o","ò","o","ô","o","õ","o","ö","o",
        "ú","u","ù","u","û","u","ü","u",
        "ç","c","ñ","n",
        "Á","A","À","A","Â","A","Ã","A","Ä","A",
        "É","E","È","E","Ê","E","Ë","E",
        "Í","I","Ì","I","Î","I","Ï","I",
        "Ó","O","Ò","O","Ô","O","Õ","O","Ö","O",
        "Ú","U","Ù","U","Û","U","Ü","U",
        "Ç","C","Ñ","N"
    )
    resultado := texto
    for de, para in mapa
        resultado := StrReplace(resultado, de, para)
    return resultado
}

; Reconhece, a partir do texto digitado no campo Entidade, qual dos 3 grupos
; RPC (Previdência Complementar) se aplica — PREFEITURA (todos os códigos),
; FAS ou CAMARA (só os marcados com X) — ver a classe "RPC" no dropdown
; "Classe de Conta" e AplicarConta, em Interface.ahk. Sem diferenciar
; maiúscula/minúscula/acento (ex.: "Câmara", "camara" e "CAMARA" batem
; igual). Retorna "" se a Entidade não bater com nenhum dos 3 grupos —
; nesse caso AplicarConta avisa o usuário em vez de aplicar código errado.
DetectarGrupoRPC(textoEntidade) {
    normalizado := StrUpper(RemoverAcentos(Trim(textoEntidade)))
    if InStr(normalizado, "PREFEITURA")
        return "PREFEITURA"
    if InStr(normalizado, "CAMARA")
        return "CAMARA"
    if InStr(normalizado, "FAS")
        return "FAS"
    return ""
}

; Junta uma lista de valores com vírgula, pra mensagens/logs legíveis.
JuntarValores(lista) {
    texto := ""
    for valor in lista
        texto .= (texto = "" ? "" : ",") . valor
    return texto
}

; Extrai da string TODA sequência de dígitos, não importa o separador usado
; entre elas (vírgula, espaço, ponto-e-vírgula, traço, texto qualquer...).
; Usado pra deixar o usuário digitar códigos de conta avulsos na interface
; (ex.: "100, 200, 300" ou "100 200 300" ou "100/200/300" — tudo funciona
; igual) em vez de exigir um formato exato — ver AplicarConta, em
; Interface.ahk.
DividirCodigos(texto) {
    lista := []
    pos := 1
    while RegExMatch(texto, "\d+", &m, pos) {
        lista.Push(m[0])
        pos := m.Pos + m.Len
    }
    return lista
}

; Isola, dentro do texto capturado da página inteira, só um trecho a partir
; de "campo" — evita que valores de OUTRO campo (ex.: Conta aparecendo
; junto com Tipo Folha no mesmo texto) sejam confundidos com valores do
; campo atual.
;
; Tentativa anterior usava o campo SEGUINTE na página (ex.: "Matrícula" pra
; Conta) como fronteira final. Isso quebrou na prática: capturando a página
; de verdade (texto real fornecido pelo usuário), "Matrícula" simplesmente
; NÃO aparecia no texto capturado (a seção onde ela fica parecia não estar
; expandida no momento) — sem a âncora, a função silenciosamente caía no
; fallback de "sem âncora, usa o texto inteiro", que é exatamente o
; problema que a função tentava evitar. Uma âncora que pode nem estar
; presente é frágil demais pra depender dela.
;
; Em vez de fronteira final por texto, usa uma JANELA de tamanho fixo a
; partir do campo: "campo" (ex.: "Tipo Folha") pode aparecer MAIS de uma
; vez na página (rótulo do filtro + cabeçalho da tabela de resultados,
; repetido logo em seguida — confirmado no texto real) — pegar a PRIMEIRA
; ocorrência arriscaria cair num elemento ACIMA e sem relação com a tabela
; de resultados; por isso usa a ÚLTIMA ocorrência de "campo" no texto, que
; é sempre a mais próxima da lista de valores selecionados (confirmado no
; texto real pra Tipo Folha E Conta). tamanhoJanela generoso o bastante pra
; caber uma lista de códigos inteira sem alcançar o próximo campo da página.
TrechoDoCampo(texto, campo, tamanhoJanela := 2000) {
    posCampo := 0
    posBusca := 1
    Loop {
        achado := InStr(texto, campo,, posBusca)
        if !achado
            break
        posCampo := achado
        posBusca := achado + 1
    }

    if !posCampo
        return texto
    return SubStr(texto, posCampo, tamanhoJanela)
}
