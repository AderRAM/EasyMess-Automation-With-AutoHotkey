; =====================================================================
; Utilitarios.ahk
; Funcoes genericas/compartilhadas, usadas por mais de um modulo (ou que
; nao pertencem especificamente a uma pagina): deteccao de pagina, espera,
; log, controles de pausa/reset, localizacao via Ctrl+F, captura de texto
; da tela, e pequenos helpers de string/data. Portado do V2 sem mudanca de
; comportamento.
; =====================================================================

; Detecta se é Chrome ou Firefox e ajusta janelaAlvo/g_Navegador de acordo
; (Chrome e Firefox fecham o Ctrl+F de jeitos diferentes — ver
; FecharBuscaCtrlF). Prioridade Chrome > Firefox se os dois estiverem
; abertos. Retorna false se não achou nenhum dos dois.
DetectarNavegador() {
    global janelaAlvo, g_Navegador

    if WinExist("ahk_exe chrome.exe") {
        janelaAlvo := "ahk_exe chrome.exe"
        g_Navegador := "CHROME"
        return true
    }
    if WinExist("ahk_exe firefox.exe") {
        janelaAlvo := "ahk_exe firefox.exe"
        g_Navegador := "FIREFOX"
        return true
    }
    return false
}

; Lê o conteúdo real da tela (via seleção + cópia) e classifica em qual
; página estamos, em vez de confiar em sleeps fixos. Retorna: "PAGINA1",
; "PAGINA2", "CARREGANDO", "SEM_LEITURA" ou "DESCONHECIDA".
DetectarPagina() {
    global janelaAlvo

    if !WinActive(janelaAlvo) {
        WinActivate(janelaAlvo)
        AguardarJanelaAtiva(janelaAlvo, 1)
    }

    A_Clipboard := ""
    EnviarTecla("^a")
    Aguardar(100)
    EnviarTecla("^c")

    if !AguardarClipboard(1.5) {
        ; DESPRENDER FOCO: a leitura veio vazia — provavelmente o foco está
        ; preso numa caixa de texto (ali Ctrl+A só seleciona o CAMPO, não a
        ; página inteira, então Ctrl+C não traz o texto esperado). Ctrl+F
        ; força o foco pro nível da página/find-bar não importa onde
        ; estava antes (confirmado: essa é a causa de "Aguardar PAGINA1"
        ; ficar preso em SEM_LEITURA por ~5s logo após Aplicar Conta/Tipo
        ; Folha, até a recuperação via "Voltar" acabar fazendo a mesma
        ; coisa por acidente). Só tenta UMA vez, e só quando necessário
        ; (aqui, depois da leitura vazia) — não em toda chamada.
        RegistrarEvento("Desprender foco (Ctrl+F)", "AVISO", "1a leitura veio vazia, tentando destravar e ler de novo")

        EnviarTecla("^f")
        Aguardar(150)
        EnviarTecla("^a")
        Aguardar(60)
        EnviarTecla("{BackSpace}")
        Aguardar(100)
        EnviarTexto("Referência") ; nao precisa achar nada — so abrir/fechar a busca ja destrava o foco
        Aguardar(150)
        EnviarTecla("{Enter}")
        Aguardar(120)
        FecharBuscaCtrlF(false, false)

        A_Clipboard := ""
        EnviarTecla("^a")
        Aguardar(100)
        EnviarTecla("^c")

        if !AguardarClipboard(1.5) {
            ; sem {Left}: nada foi selecionado (foco num botão), então não há o
            ; que desfazer — e {Left} aqui poderia mover o foco pro elemento vizinho.
            return "SEM_LEITURA"
        }
    }

    texto := A_Clipboard
    EnviarTecla("{Left}") ; desfaz a seleção

    ; PAGINA2 sem resultados mostra "Sem informações..." em vez de "N
    ; resultado(s) encontrado(s)" — as duas contam como PAGINA2.
    if InStr(texto, "resultado(s) encontrado(s)")
        return "PAGINA2"
    if InStr(texto, "Sem informações para serem listadas")
        return "PAGINA2"

    ; CARREGANDO: a consulta ainda processa no servidor e a tela continua
    ; mostrando o formulário da Página 1 — sinalizado pela QUANTIDADE de
    ; vezes que "Executar" aparece na tela. CORRIGIDO: o limiar de 1 no
    ; Firefox (valor antigo, presumivelmente calibrado numa página
    ; diferente) fazia a Página 1 IDLE (que já mostra "Executar" 1x sozinha,
    ; ex.: botões "Executar"/"Limpar" do formulário) ser lida como
    ; CARREGANDO pra sempre — o ciclo nunca avançava, só ficava selecionando
    ; a tela em loop até estourar TIMEOUT_MAX_CARREGANDO_SEGUNDOS. 2x em
    ; ambos os navegadores (mesmo limiar do Chrome, que nunca teve esse problema).
    qtdExecutar := StrSplit(texto, "Executar").Length - 1
    limiarCarregando := 2
    if (qtdExecutar >= limiarCarregando)
        return "CARREGANDO"

    if InStr(texto, "Referência")
        return "PAGINA1"

    return "DESCONHECIDA"
}

; Verifica Esc/F2/F3 por ESTADO FÍSICO da tecla (GetKeyState), não pelos
; hotkeys do AHK — o hook de hotkeys pode não reagir a tempo enquanto o
; script manda Send()/SendText() sem parar durante um ciclo. Chamada com
; frequência (RegistrarEvento, AguardarPagina).
VerificarControles() {
    global g_Pausado, g_Gui, g_CicloEmExecucao

    if GetKeyState("Esc", "P")
        ExitApp()

    ; Painel em foco durante um ciclo rodando: inútil tentar mexer nele
    ; (as teclas do ciclo continuariam indo pro painel, não pro navegador)
    ; — pausa automaticamente em vez de deixar isso quebrar silenciosamente.
    if (g_CicloEmExecucao && !g_Pausado && IsObject(g_Gui) && WinActive("ahk_id " . g_Gui.Hwnd)) {
        TrayTip("AutoHotkey", "Pausado automaticamente: painel ganhou foco com o ciclo rodando.", 1)
        DefinirPausado(true) ; nao usa Pausar() pra nao duplicar o TrayTip generico dela
    }

    if GetKeyState("F3", "P") {
        while GetKeyState("F3", "P") ; espera soltar
            Sleep(30)
        ResetarScript()
    }

    if GetKeyState("F2", "P") {
        while GetKeyState("F2", "P") ; espera soltar
            Sleep(30)
        Pausar() ; em Interface.ahk, só pausa (idempotente); retomar é sempre F1
    }

    ; Pausado: só dormindo, sem Send/SendText — o hook de hotkeys nativo
    ; (F1::/F3::) já responde sem problema aqui, por isso F1 não precisa de
    ; checagem manual. F2 também não (seria um no-op, já pausado). F3
    ; continua checado manualmente por consistência com Esc.
    while (g_Pausado) {
        Sleep(150)
        if GetKeyState("Esc", "P")
            ExitApp()
        if GetKeyState("F3", "P") {
            while GetKeyState("F3", "P")
                Sleep(30)
            ResetarScript()
        }
    }
}

; Substituto de Sleep() usado em todo o código de automação — cada espera
; vira um checkpoint de pausa/reset/aborto. Não usar dentro de
; VerificarControles() nem no polling de AguardarPagina (recursão).
Aguardar(ms) {
    Sleep(ms)
    VerificarControles()
}

; Substitutos de Send()/SendText() que checam pausa/reset/aborto ANTES de
; cada tecla — o atraso máximo entre apertar F2 e a automação parar é de 1
; tecla. Usar sempre estas duas; Send/SendText nativos só aparecem aqui dentro.
EnviarTecla(teclas) {
    VerificarControles()
    Send(teclas)
}

EnviarTexto(texto) {
    VerificarControles()
    SendText(texto)
}

; Fecha a busca do Ctrl+F: Shift+Tab no Chrome, 7x Tab no Firefox, seguido
; de no máximo 1 Enter opcional. Mecanismo compartilhado por
; LocalizarEFocar e InserirCampoMultiSelect (Pagina1.ahk). "Exportar em
; PDF" (Pagina2.ahk) usa seu próprio mecanismo, não esta função.
;
; Firefox: os 7 Tabs só MOVEM o foco até o botão "X" da barra, sem fechá-la
; — precisa de um Enter depois pra ativar o X de verdade. Esse Enter já
; cumpre o papel do "comEnter" do Chrome, por isso comEnter/esperarSemEnter
; são ignorados em Firefox.
;
; comEnter (default true) - CHROME: manda um Enter depois da espera
;                  pós-fechamento.
; esperarSemEnter (default true) - CHROME: só importa com comEnter=false —
;                  se true, ainda espera delayCurto; se false, retorna na
;                  hora (uso de LocalizarEFocar).
FecharBuscaCtrlF(comEnter := true, esperarSemEnter := true) {
    global delayCurto, g_Navegador

    if (g_Navegador = "FIREFOX") {
        Loop 7
            EnviarTecla("{Tab}")
        ; Ativa o botão "X" que os 7 Tabs só focaram, fechando a barra pra valer.
        Aguardar(delayCurto)
        EnviarTecla("{Enter}")
        return
    }

    EnviarTecla("+{Tab}")

    if (comEnter) {
        Aguardar(delayCurto)
        EnviarTecla("{Enter}")
    } else if (esperarSemEnter) {
        Aguardar(delayCurto)
    }
}

; Espera (com polling) até a página esperada aparecer. paginaDetectada
; (saída por referência) guarda o último valor lido, pra mensagem de erro
; em caso de timeout. intervaloChecagemMs (padrão 400ms) controla de quanto
; em quanto tempo DetectarPagina() roda de novo — F2/F3/Esc continuam
; checados a cada 100ms independente disso.
AguardarPagina(paginaEsperada, timeoutSegundos, &paginaDetectada, intervaloChecagemMs := 400) {
    global TIMEOUT_MAX_CARREGANDO_SEGUNDOS
    inicio := A_TickCount
    inicioAbsoluto := A_TickCount
    Loop {
        VerificarControles()
        paginaDetectada := DetectarPagina()
        if (paginaDetectada = paginaEsperada) {
            ; limiteLentoMs=10000 (nao os 5000 padrao): essa espera dispara
            ; com muita frequencia perto do padrao, sem ser de fato um
            ; problema — so alarma se passar de 10s de verdade.
            RegistrarEvento("Aguardar " . paginaEsperada, "OK", "esperou " . (A_TickCount - inicioAbsoluto) . "ms", 10000)
            return true
        }

        ; Enquanto CARREGANDO, o timeout normal é resetado a cada checagem
        ; (a consulta visivelmente ainda está em andamento) — só um teto bem
        ; mais generoso evita esperar pra sempre se a tela realmente travar.
        if (paginaDetectada = "CARREGANDO") {
            inicio := A_TickCount
            if ((A_TickCount - inicioAbsoluto) / 1000 > TIMEOUT_MAX_CARREGANDO_SEGUNDOS) {
                RegistrarEvento("Aguardar " . paginaEsperada, "ERRO", "TIMEOUT (travado em CARREGANDO) apos " . (A_TickCount - inicioAbsoluto) . "ms", 10000)
                return false
            }
        } else if ((A_TickCount - inicio) / 1000 > timeoutSegundos) {
            RegistrarEvento("Aguardar " . paginaEsperada, "ERRO", "TIMEOUT apos " . (A_TickCount - inicio) . "ms, ultima pagina detectada='" . paginaDetectada . "'", 10000)
            return false
        }
        ; Sleep em pedaços de 100ms até completar intervaloChecagemMs.
        Loop Max(1, Round(intervaloChecagemMs / 100)) {
            VerificarControles()
            Sleep(100)
        }
    }
}

; Substituto "pausável" de WinWaitActive() nativo — espera em pedaços de
; ~100ms checando VerificarControles, em vez de bloquear o script inteiro
; (o nativo não dá chance de checar F2/F3/Esc durante a espera). Retorna
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

; Espera (com polling) até a URL/caminho em foco deixar de bater com
; qualquer um dos domínios conhecidos (ver DetectarEntidadeURL, CapturarUrlOuCaminho)
; — sinal de que saímos da página do sistema. Usado pra detectar a janela
; nativa "Salvar como" tomando o foco (ver ValidarEExportarPagina2,
; Pagina2.ahk) SEM depender do título da janela (que no Firefox demora a
; ficar "pronta" mesmo depois de WinActive reportar true — ver comentário
; lá). Ignora leituras vazias (falha de captura/clipboard, não confirma
; nada).
;
; TRAVA DE SEGURANÇA: a janela "Salvar como" mostra um CAMINHO DE PASTA
; (ex.: "Downloads", "C:\..."), nunca uma URL — então um texto capturado
; que bate com "https://" e MESMO ASSIM não reconhece nenhum domínio
; conhecido não é a janela Salvar como, é um SITE ERRADO de verdade (aba
; trocada, navegação indevida, etc.). Nesse caso pausa IMEDIATAMENTE (não
; só avisa) em vez de seguir tentando digitar caminho/nome de arquivo às
; cegas num site desconhecido.
AguardarSairDoSite(timeoutSegundos, intervaloChecagemMs := 400) {
    inicio := A_TickCount
    Loop {
        VerificarControles()
        texto := CapturarUrlOuCaminho()

        if (texto != "" && DetectarEntidadeURL(texto) = "") {
            if InStr(texto, "https://") {
                TrayTip("Pausado: site inesperado", "URL fora dos sites conhecidos: " . texto, 3)
                DefinirPausado(true)
                VerificarControles() ; bloqueia aqui ate F1 retomar
                inicio := A_TickCount ; tempo pausado nao conta pro timeout
                continue
            }
            return true ; sem https:// -- caminho de pasta, Salvar como presumido em foco
        }

        if ((A_TickCount - inicio) / 1000 > timeoutSegundos)
            return false

        Loop Max(1, Round(intervaloChecagemMs / 100)) {
            VerificarControles()
            Sleep(100)
        }
    }
}

; Mesma ideia de AguardarJanelaAtiva, pra ClipWait() nativo. Assume que o
; chamador já limpou A_Clipboard antes do Ctrl+C.
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

; Registra um evento no log (log_acoes.csv) com o tempo decorrido desde o
; último evento. Acima de limiteLentoMs (padrão: LIMITE_ACAO_LENTA_MS), marca
; Lento=SIM e avisa via TrayTip. status sugerido: "OK", "AVISO", "ERRO", "ABORTADO".
; limiteLentoMs (opcional): sobrescreve o limiar padrão pra essa chamada só —
; ver "Aguardar PAGINA1/PAGINA2" (AguardarPagina, mais abaixo), que passa 10000.
RegistrarEvento(etapa, status := "OK", detalhes := "", limiteLentoMs := 0) {
    global g_CicloAtual, g_UltimoTickAcao, logAcoes, LIMITE_ACAO_LENTA_MS

    if (limiteLentoMs = 0)
        limiteLentoMs := LIMITE_ACAO_LENTA_MS

    agora   := A_TickCount
    duracao := (g_UltimoTickAcao = 0) ? 0 : (agora - g_UltimoTickAcao)
    g_UltimoTickAcao := agora

    lento := (duracao > limiteLentoMs) ? "SIM" : "NAO"
    timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")

    linha := timestamp . ";" . g_CicloAtual . ";" . etapa . ";" . duracao . ";"
           . limiteLentoMs . ";" . lento . ";" . status . ";" . detalhes . "`n"

    ; O arquivo de log pode estar momentaneamente travado — tenta algumas
    ; vezes em vez de derrubar o script por causa de uma linha de log.
    Loop 5 {
        try {
            FileAppend(linha, logAcoes)
            break
        } catch {
            VerificarControles()
            Sleep(100)
        }
    }

    ; Etapas sabidamente lentas (janela "Salvar como"; "Limpar caixa X"/
    ; "Inserir X" em InserirCampoMultiSelect, que capturam até 200000 chars
    ; da página) não disparam TrayTip — ainda ficam marcadas "lento=SIM" no
    ; CSV, só não viram ruído repetido. "Inicio ciclo"/"Inicio ciclo
    ; e-Social" tambem entram aqui: a duracao medida ali inclui o tempo que
    ; o USUARIO levou pra apertar Executar/F1 (g_UltimoTickAcao so eh
    ; resetado explicitamente em acoes como InserirContas/InserirTipoFolha,
    ; nao no inicio do ciclo em si) — nao eh lentidao da automacao, entao
    ; nao faz sentido alarme nenhum aqui, mesmo etapaLentaConhecida.
    etapaLentaConhecida := (etapa = "Janela Salvar como")
        || (etapa = "Inicio ciclo")
        || (etapa = "Inicio ciclo e-Social")
        || InStr(etapa, "Limpar caixa ") = 1
        || InStr(etapa, "Inserir ") = 1
    if (lento = "SIM" && !etapaLentaConhecida)
        TrayTip("Ação lenta detectada", g_CicloAtual . " - " . etapa . " levou " . duracao . "ms", 1)

    ; Chamado no FIM (não no início) — assim uma pausa acionada aqui não
    ; entra na duracao_ms do evento que acabou de ser registrado.
    VerificarControles()
}

; Localiza um texto via Ctrl+F e, a partir dali, dá N Tabs — usado para
; "Referência"/"Executar"/"Voltar" (página 1). "Exportar em PDF" (página
; 2) tem seu próprio código em Pagina2.ahk.
; ativarComEnter: Enter extra pra "ativar" o elemento encontrado antes dos Tabs.
; tabsExtras: Tabs além do elemento encontrado pra chegar no input real
;             (0 pra botões, já focados).
; hopsFirefox (default -1): em Firefox, substitui o mecanismo de 7 Tabs de
;             FecharBuscaCtrlF por essa quantidade de Shift+Tab simples —
;             alguns alvos (ex.: "Voltar", com 3) fecham a busca diferente
;             dos demais. -1 mantém o comportamento padrão.
LocalizarEFocar(textoAlvo, tabsExtras := 0, ativarComEnter := false, hopsFirefox := -1) {
    global janelaAlvo, delayCurto, g_Navegador

    if !WinActive(janelaAlvo) {
        WinActivate(janelaAlvo)
        AguardarJanelaAtiva(janelaAlvo, 2)
    }

    EnviarTecla("^f")
    Aguardar(150)
    EnviarTecla("^a") ; seleciona o texto da busca anterior
    Aguardar(60)
    EnviarTecla("{BackSpace}") ; garante a caixa de busca vazia
    Aguardar(delayCurto)
    EnviarTexto(textoAlvo)
    Aguardar(150)
    EnviarTecla("{Enter}")
    Aguardar(120)

    Aguardar(delayCurto)
    if (g_Navegador = "FIREFOX" && hopsFirefox >= 0) {
        Loop hopsFirefox {
            EnviarTecla("+{Tab}")
            Aguardar(delayCurto)
        }
        if (ativarComEnter)
            EnviarTecla("{Enter}")
    } else {
        FecharBuscaCtrlF(ativarComEnter, false) ; esperarSemEnter=false: o loop tabsExtras abaixo já espera antes do 1º Tab
    }

    Loop tabsExtras {
        Aguardar(delayCurto)
        EnviarTecla("{Tab}")
    }

    RegistrarEvento("Localizar: " . textoAlvo, "OK", "tabsExtras=" . tabsExtras . " ativarComEnter=" . ativarComEnter)
}

; DIAGNÓSTICO: captura um resumo do texto atual da tela e devolve já
; sanitizado pra caber numa célula do CSV (sem quebras de linha nem ';').
CapturarResumoPagina(maxChars := 300) {
    global janelaAlvo

    if !WinActive(janelaAlvo) {
        WinActivate(janelaAlvo)
        AguardarJanelaAtiva(janelaAlvo, 1)
    }

    A_Clipboard := ""
    EnviarTecla("^a")
    Aguardar(30) ; minimo pra selecao registrar antes do copy
    EnviarTecla("^c")

    if !AguardarClipboard(1) {
        return "[SEM_LEITURA]"
    }

    EnviarTecla("{Left}") ; desfaz a selecao o quanto antes
    texto := A_Clipboard

    texto := StrReplace(texto, "`r`n", " | ")
    texto := StrReplace(texto, "`n", " | ")
    texto := StrReplace(texto, ";", ",")

    if (StrLen(texto) > maxChars)
        texto := SubStr(texto, 1, maxChars) . "...(truncado, total=" . StrLen(texto) . " chars)"

    return texto
}

; Volta para a página 1, confirmando via DetectarPagina() em vez de sleep
; fixo. O botão "Voltar" fica na Página 2, mas essa função é chamada de
; vários lugares — por isso fica aqui como utilitário compartilhado.
VoltarParaPrimeiraPagina(dataTag, logFile) {
    global delayCurto, delayMedio, janelaAlvo
    global TABS_APOS_VOLTAR

    if !WinActive(janelaAlvo) {
        WinActivate(janelaAlvo)
        AguardarJanelaAtiva(janelaAlvo, 2)
    }

    ; Assentamento extra logo apos fechar "Salvar como" — mesma logica do
    ; Aguardar(1500) quando ela ABRE (Firefox integra a janela no proprio
    ; processo e demora a devolver o foco/estado de verdade pra pagina, ver
    ; comentario em ValidarEExportarPagina2/Pagina2.ahk). Sem isso, o Ctrl+F
    ; de "Voltar" logo abaixo pode disparar cedo demais.
    Aguardar(800)

    ; DIAGNÓSTICO: captura o estado da tela ANTES de tentar achar "Voltar" —
    ; se o Voltar continuar sem efeito (ver "Voltar sem efeito ainda" mais
    ; abaixo), esse log mostra o que realmente estava na tela na hora,
    ; em vez de só um timeout sem contexto.
    RegistrarEvento("Estado antes de Voltar", "OK", TrechoDoCampo(CapturarResumoPagina(2000), "Exportar", 800))

    ; hopsFirefox=3: em Firefox "Voltar" fecha a busca e chega no botão
    ; certo só com 3x Shift+Tab (ver LocalizarEFocar).
    LocalizarEFocar("Voltar", TABS_APOS_VOLTAR, false, 3)

    ; TESTE: "wiggle" desativado (Tab pra frente + Shift+Tab de volta, que
    ; "repousava" no botão via navegação normal em vez da barra de busca).
    ; Nunca causou reexportação de verdade (log nunca mostrou um 2º
    ; "Confirmar Exportar em PDF" seguido de um Voltar), então comentado
    ; pra confirmar se o Enter direto (sem o wiggle) funciona igual —
    ; reativar se o Voltar parar de funcionar sem isso.
    ; Aguardar(60)
    ; EnviarTecla("{Tab}")
    ; Aguardar(60)
    ; EnviarTecla("+{Tab}")

    Aguardar(delayMedio) ; tempo de assentamento antes do Enter

    ; Reenvia o Enter se a página não mudar dentro de 800ms.
    chegouPagina1 := false
    Loop 2 {
        EnviarTecla("{Enter}")
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

; Remove acentos comuns do português (maiúsc./minúsc.), pra comparar texto
; sem depender de como o usuário digitou (ex.: "Câmara" -> "Camara").
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

; Reconhece qual grupo RPC (PREFEITURA/FAS/CAMARA) a Entidade digitada
; representa, sem diferenciar maiúscula/minúscula/acento (ver classe "RPC"
; em AplicarConta, Interface.ahk). Retorna "" se não bater com nenhum.
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

; Reconhece qual das 6 entidades (PREFEITURA/IPAM/CAMARA/FAS/PENSIONISTAS/
; INATIVOS) um texto parece representar. Serve tanto pro campo Entidade
; (texto curto, ex.: "Câmara") quanto pra um CAMINHO DE PASTA inteiro (ex.:
; "...\CONSULTA_EVENTOS\PREFEITURA") — usado em ExecutarProcessamento,
; Interface.ahk, pra avisar se a pasta de destino parece ser de outra
; entidade (convenção do usuário de nomear a última pasta com o nome da
; entidade). Retorna "" se não reconhecer nada — path genérico, sem nome de
; entidade nenhum, não deve gerar aviso (evita falso positivo).
ClassificarEntidade(texto) {
    normalizado := StrUpper(RemoverAcentos(texto))
    if InStr(normalizado, "PREFEITURA")
        return "PREFEITURA"
    if InStr(normalizado, "CAMARA")
        return "CAMARA"
    if InStr(normalizado, "FAS")
        return "FAS"
    if InStr(normalizado, "IPAM")
        return "IPAM"
    ; "FAPSPENS" — nome real da pasta de Pensionistas na convenção do
    ; usuário (ver captura de tela do "Procurar Pasta"), não contém
    ; "Pensionista" por extenso.
    if InStr(normalizado, "PENSIONISTA") || InStr(normalizado, "FAPSPENS")
        return "PENSIONISTAS"
    if InStr(normalizado, "INATIVO")
        return "INATIVOS"
    return ""
}

; Classifica um texto de Entidade OU Tipo Folha em "PENSIONISTAS",
; "INATIVOS" ou "NORMAL" (IPAM/Prefeitura/Câmara/FAS) — usado só pra
; comparar os dois campos e avisar de uma combinação inconsistente (ver
; ExecutarProcessamento/ExecutarProcessamentoES, Interface.ahk), nunca pra
; bloquear nada sozinho.
ClassificarGrupoFolha(texto) {
    normalizado := StrUpper(RemoverAcentos(texto))
    if InStr(normalizado, "PENSIONISTA")
        return "PENSIONISTAS"
    if InStr(normalizado, "INATIVO")
        return "INATIVOS"
    return "NORMAL"
}

; ---------------------------------------------------------------------
; SUBSTITUÍDA por DetectarEntidadeURL (abaixo) — essa aqui lia o cabeçalho
; da PÁGINA INTEIRA (CapturarResumoPagina, Ctrl+A/Ctrl+C caro) só pra achar
; o nome do órgão. A URL (Ctrl+L/Ctrl+C, bem mais barato — só a barra de
; endereço, não a página) já identifica o órgão pelo domínio, então essa
; ficou sem uso. Mantida comentada (não apagada) por ora, caso o
; reconhecimento por texto do cabeçalho volte a ser útil.
; ---------------------------------------------------------------------
; DetectarOrgaoPagina(texto) {
;     normalizado := StrUpper(RemoverAcentos(texto))
;     if InStr(normalizado, "CAMARA DE VEREADORES")
;         return "CAMARA"
;     if InStr(normalizado, "IPAM INATIVOS")
;         return "INATIVOS_PENSIONISTAS"
;     if InStr(normalizado, "INSTITUTO DE PREVIDENCIA E ASSISTENCIA MUNICIPAL")
;         return "IPAM"
;     if InStr(normalizado, "MUNICIPIO DE CAXIAS DO SUL")
;         return "PREFEITURA"
;     if InStr(normalizado, "FUNDACAO DE ASSISTENCIA SOCIAL")
;         return "FAS"
;     return ""
; }

; Captura a URL/caminho atual via Ctrl+L + Ctrl+C — bem mais barato que
; CapturarResumoPagina/DetectarPagina (que selecionam a PÁGINA INTEIRA):
; Ctrl+L só foca/seleciona a barra de endereço. NÃO faz WinActivate(janelaAlvo)
; de propósito — o objetivo é ler o que estiver com foco NA HORA, seja a
; aba do navegador (retorna a URL normal) ou, se nesse momento o foco
; estiver na janela nativa "Salvar como" (Ctrl+L também funciona nela,
; focando o caminho/breadcrumb — mesmo mecanismo usado em
; ValidarEExportarPagina2, Pagina2.ahk, pra digitar caminhoDownload),
; retorna o caminho mostrado ali (ex.: "Downloads" ou o último caminho
; usado) — que não bate com nenhum domínio conhecido (ver
; DetectarEntidadeURL) e por isso serve de sinal indireto de que saímos da
; página do sistema (ex.: a janela Salvar como abriu e roubou o foco).
; NÃO manda Esc pra "cancelar" a edição da barra no final (versão antiga
; mandava) — Esc é o kill switch físico checado em VerificarControles()
; (GetKeyState("Esc", "P") -> ExitApp()), e um Esc ENVIADO pelo script é
; visto momentaneamente como fisicamente pressionado (o key-hold de
; SetKeyDelay, ver início do script) enquanto ainda está "down" — o
; VerificarControles() chamado logo em seguida (ex.: no polling de
; AguardarSairDoSite) pega esse próprio Esc e mata o script na hora, sem
; log nenhum (foi exatamente isso que aconteceu — CapturarUrlOuCaminho foi
; a única função nesse script inteiro que mandava Esc). Não precisa: quem
; chama essa função sempre dá um Ctrl+L novo antes de digitar qualquer
; coisa, então deixar a barra ainda selecionada entre uma leitura e outra
; não atrapalha nada.
CapturarUrlOuCaminho() {
    A_Clipboard := ""
    EnviarTecla("^l")
    Aguardar(80)
    EnviarTecla("^c")

    if !AguardarClipboard(1)
        return ""

    return A_Clipboard
}

; Reconhece qual ÓRGÃO a URL/caminho capturado (ver CapturarUrlOuCaminho)
; representa, pelo domínio do sistema. Retorna "" se não bater com nenhum
; domínio conhecido — sinal de que não estamos na página do sistema (ex.:
; aba errada, ou algo como a janela "Salvar como" com foco no lugar).
DetectarEntidadeURL(texto) {
    if InStr(texto, "admrhipam.caxias")
        return "IPAM"
    if InStr(texto, "admrhcamara.caxias")
        return "CAMARA"
    if InStr(texto, "admrhinativos.caxias")
        return "INATIVOS_PENSIONISTAS"
    if InStr(texto, "admrhfas.caxias")
        return "FAS"
    if InStr(texto, "admrh.caxias")
        return "PREFEITURA"
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
; entre elas. Usado pra deixar o usuário digitar códigos de conta avulsos
; na interface (ex.: "100, 200, 300" ou "100/200/300") sem exigir um
; formato exato — ver AplicarConta, em Interface.ahk.
DividirCodigos(texto) {
    lista := []
    pos := 1
    while RegExMatch(texto, "\d+", &m, pos) {
        lista.Push(m[0])
        pos := m.Pos + m.Len
    }
    return lista
}

; Isola, no texto capturado da página inteira, uma JANELA de tamanho fixo
; a partir da ÚLTIMA ocorrência de "campo" — evita confundir valores de
; outro campo (ex.: Conta com Tipo Folha) e evita a PRIMEIRA ocorrência,
; que pode ser só o rótulo do filtro, não a tabela de resultados.
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

; Recorta do ÚLTIMO "campo" até a próxima âncora (ex.: "Referência").
; Se não achar a âncora, cai no comportamento antigo (janela de 2000 chars).
TrechoDoCampoAte(texto, campo, ancoraFim) {
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
    posFim := InStr(texto, ancoraFim,, posCampo + StrLen(campo))
    if posFim
        return SubStr(texto, posCampo, posFim - posCampo)
    return SubStr(texto, posCampo, 2000)
}

; Devolve um Map: código -> linha inteira ("12" -> "12 - Rescisão Complementar").
; Cada linha "código - descrição" é uma categoria. Só conta o número do INÍCIO
; da linha, então "2" não casa com "12" nem com "22".
ExtrairCodigosSelecionados(trecho) {
    codigos := Map()
    for linha in StrSplit(trecho, " | ") {
        linha := Trim(linha, " `t`r`n")
        if RegExMatch(linha, "^(\d+) - \S", &m)
            codigos[m[1]] := linha
    }
    return codigos
}
