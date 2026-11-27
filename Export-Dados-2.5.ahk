; =====================================================================
; Export-Dados-2.4.ahk  (AutoHotkey v2)
; Exportador automático — percorre um intervalo de meses (de data1 até
; data2) exportando um relatório por mês via navegação com teclado. Cobre 2
; fluxos (abas separadas no painel — ver Interface.ahk): FAPS
; e e-Social (Consultas Dinâmicas → Consulta Eventos, 4 portais).

#Requires AutoHotkey v2.0
#SingleInstance Force
SetTitleMatchMode(2)
SetKeyDelay(40, 40)   ; delay entre teclas do Send — ajuste se a exportação for lenta

#Include modulos\Utilitarios.ahk
#Include modulos\Pagina1.ahk
#Include modulos\Pagina2.ahk
#Include modulos\EntrePaginas.ahk
#Include modulos\ESocial.ahk
#Include modulos\Interface.ahk

; ============================ CONFIGURAÇÕES ============================
data1   := "202607"          ; AAAAMM — mês mais recente (início do processamento)
data2   := "202304"          ; AAAAMM — mês mais antigo (fim do processamento)

; entidade: definido pelo usuario na interface (painel de controle), a cada uso.
; Fica separado do sufixo de classe (que so tem os codigos de conta).
; o prefixo final do arquivo é montado juntando os dois (ver InserirContas, em Pagina1.ahk). 
; Sem valor padrão fixo aqui — CarregarConfiguracoes() (em
; Interface.ahk) recupera o último valor usado a partir de config_v3.ini.
entidade := ""

prefix  := entidade . "874_875_876_877_878_879_" ; Prefixo/sufixo (recalculado assim que uma entidade/classe for escolhida)

ARQUIVO_ESTADO_PREFIX := A_ScriptDir . "\classe_atual.txt"
if FileExist(ARQUIVO_ESTADO_PREFIX)
    prefix := Trim(FileRead(ARQUIVO_ESTADO_PREFIX))

; --- Classes de contas (usadas pelo dropdown "Classe de Conta" + botão
; "Aplicar Conta" na interface — ver Interface.ahk) ---
; Cada classe tem sua lista de códigos e o SUFIXO de nome de arquivo
; correspondente (sem a entidade — essa vem da variavel "entidade" acima).
CLASSE_A := ["874", "875", "876", "877", "878", "879"]
CLASSE_S := ["9081", "9084", "9086", "9089", "9091", "9094"] ; BASE
CLASSE_D := ["9085", "9082", "9087", "9090", "9095", "9092"] ; PATRONAL

SUFIXO_A := "874_875_876_877_878_879_"
SUFIXO_S := "BASE_9081_9084_9086_9089_9091_9094_"
SUFIXO_D := "PATRONAL_9085_9082_9087_9090_9095_9092_"

;   (Prefeitura recebe TODOS os códigos acima, marcados com X ou não)
CLASSE_RPC_PREFEITURA := ["864", "866", "517", "9070", "9071", "9072", "9073", "9074", "9075", "880", "1045", "1046", "1047"]
CLASSE_RPC_FAS        := ["864", "866", "9070", "9072", "9073", "9074", "9075"]
CLASSE_RPC_CAMARA     := ["864", "9070", "9073", "9075"]

SUFIXO_RPC_PREFEITURA := "RPC_864_866_517_9070_9071_9072_9073_9074_9075_880_1045_1046_1047_"
SUFIXO_RPC_FAS        := "RPC_864_866_9070_9072_9073_9074_9075_"
SUFIXO_RPC_CAMARA     := "RPC_864_9070_9073_9075_"

; --- Tipo da folha não afeta o prefixo do nome de arquivo, só o filtro "Tipo Folha" na página.
; Também usada pela aba e-Social.
TIPO_FOLHA_NORMAL       := ["1", "12", "16", "22", "4"]  ; IPAM, Prefeitura, Câmara, FAS
TIPO_FOLHA_PENSIONISTAS := ["2", "10", "32", "33"]
TIPO_FOLHA_INATIVOS     := ["1", "9", "22", "23"]


; 8401 a 8412 sao todos inseridos juntos em todo ciclo, só pra Prefeitura/IPAM/
; Câmara (não existe pra Inativos/Pensionistas).
ESOCIAL_CONTA_PREFEITURA := ["476", "545", "478", "485", "398", "746", "747", "722", "542", "845", "873", "546", "547", "851", "543", "852", "848", "541", "872", "849", "838", "853", "484", "739", "840"]
ESOCIAL_CONTA_IPAM       := ["476", "544", "478", "485", "398", "746", "747", "722", "542", "845", "873", "546", "851", "543", "852", "848", "541", "872", "849", "853", "484", "739", "840"]
ESOCIAL_CONTA_CAMARA     := ["476", "545", "478", "485", "398", "746", "747", "722", "542", "845", "851", "543", "852", "848", "541", "849", "853", "484", "739", "840"]

; Mesma lista serve pra Inativos E Pensionistas
ESOCIAL_CONTA_INATIVOS_PENSIONISTAS := ["476", "545", "478", "485", "398", "746", "747", "722", "7849", "7852", "542", "845", "7846", "7851", "7850", "851", "852", "848", "541", "7845", "849", "853", "484", "739", "840"]

; Faixa completa de códigos do evento "IPAM Saúde - Férias" (8401 a 8412,
; um por mês do ano)
CodigosFeriasIPAMSaude() {
    codigos := []
    Loop 12
        codigos.Push(String(8400 + A_Index))
    return codigos
}

; Monta a lista completa de códigos de Conta do e-Social pra uma entidade específica.
ObterContaESocial(nomeEntidade, mes) {
    global ESOCIAL_CONTA_PREFEITURA, ESOCIAL_CONTA_IPAM, ESOCIAL_CONTA_CAMARA, ESOCIAL_CONTA_INATIVOS_PENSIONISTAS

    switch nomeEntidade {
        case "PREFEITURA":
            base := ESOCIAL_CONTA_PREFEITURA
        case "IPAM":
            base := ESOCIAL_CONTA_IPAM
        case "CAMARA":
            base := ESOCIAL_CONTA_CAMARA
        case "INATIVOS", "PENSIONISTAS":
            ; Não usa o código mensal de férias do IPAM Saúde
            return ESOCIAL_CONTA_INATIVOS_PENSIONISTAS.Clone()
        default:
            return []
    }

    lista := base.Clone()
    codigosFerias := CodigosFeriasIPAMSaude()
    lista.Push(codigosFerias*)
    return lista
}

; Caminho onde os arquivos exportados devem ser salvos. Definido pelo usuario na interface ("Pasta de
; destino") e lembrado entre execuções via config_v3.ini.
caminhoDownload := ""

; Sem valores padrão fixos aqui
; CarregarConfiguracoes() (Interface.ahk) recupera os últimos
; valores usados a partir de config_v3.ini.
data1ES     := ""
data2ES     := ""
pastaBaseES := ""
logFileES   := A_ScriptDir . "\log_ciclos_com_erro_esocial.csv"   ; log de erro/aborto separado do FAPS

logFile       := A_ScriptDir . "\log_ciclos_com_erro.csv"   ; resumo apenas dos ciclos com erro/aborto
logAcoes      := A_ScriptDir . "\log_acoes.csv"    ; linha a linha de TODAS as ações, com tempo
delayCurto  := 100          ; ms — entre passos rápidos (tabs, digitação)
delayMedio  := 800          ; ms — depois de abrir uma nova tela/janela
delayLongo  := 1500         ; ms — depois de disparar a exportação em si

; Se uma ação demorar mais que isso (ms) desde a ação anterior, ela é
; marcada como "LENTO" no log de ações, para facilitar achar gargalos.
LIMITE_ACAO_LENTA_MS := 5000

; Teto máximo (segundos) pra esperar enquanto a página estiver no estado
; "CARREGANDO".
TIMEOUT_MAX_CARREGANDO_SEGUNDOS := 60

; --- Estado interno usado para medir tempo entre ações e identificar o
; ciclo atual nos logs (não editar) ---
g_CicloAtual     := "-"
g_UltimoTickAcao := 0
g_Pausado        := false
g_PedidoReset    := false

; Marca A_TickCount da última vez que AlternarPausa() (Interface.ahk)
g_UltimoToggleTick := 0

; true enquanto Iniciar() OU IniciarESocial() (ESocial.ahk) estiver
; efetivamente rodando um lote.
g_CicloEmExecucao := false

; Navegador base
g_Navegador := "CHROME"

; true só na primeira chamada de Iniciar() depois de um F3 (Reset)
g_AutoPausarAoIniciar := (A_Args.Length > 0 && A_Args[1] = "/restarted")

;Contagem de Tabs a partir do texto localizado via Ctrl+F. 
TABS_APOS_REFERENCIA := 1   ; sequencia confirmada: Shift+Tab, Enter (ativa o rotulo), Tab 1x -> campo de data
TABS_ENTRE_CAMPOS    := 2   ; Tabs entre o campo de data e o próximo campo relevante
TABS_APOS_EXECUTAR   := 0
TABS_APOS_VOLTAR     := 0
; "Exportar em PDF" nao usa esse mecanismo — Ctrl+F + 3 Tabs direto no
; módulo Pagina2.ahk, entao nao ha uma variavel de Tabs extras para ele aqui.

; Nome da janela/aba do navegador onde o processo roda. Valor inicial aqui
; é só um placeholder.
janelaAlvo := "ahk_exe chrome.exe"

; Carrega valores salvos de uma execução anterior (config_v3.ini) por cima
; dos valores padrão acima, e então monta a janela — ver Interface.ahk.
CarregarConfiguracoes()
CriarInterface()


; F1/F2/F3/Esc aqui são só o caminho "rápido" (funciona quando o script
; está ocioso). O caminho CONFIÁVEL, que funciona mesmo com um ciclo
; rodando, é VerificarControles() (em Utilitarios.ahk)
F1:: ExecutarConformeAba() ; em Interface.ahk — despacha pra FAPS ou e-Social conforme a aba ativa, sincroniza os campos certos e salva a config antes de iniciar (ou retoma se já pausado)
F2:: Pausar() ; em Interface.ahk — só pausa; retomar é sempre F1
Esc:: ExitApp()
F3:: ResetarScript()

; //Função de reset
ResetarScript() {
    
    SalvarConfiguracoes()

    TrayTip("AutoHotkey", "Resetando...", 1)
    Sleep(500)
    Run('"' . A_AhkPath . '" /restart "' . A_ScriptFullPath . '" /restarted')
}

; ============================ FUNÇÃO PRINCIPAL
Iniciar() {
    global data1, data2, prefix, logFile, logAcoes, janelaAlvo, caminhoDownload
    global g_AutoPausarAoIniciar, g_CicloEmExecucao

    ; ---------- TRAVA: impede 2 lotes concorrentes (FAPS+FAPS, FAPS+e-Social
    ; ou e-Social+e-Social) na MESMA janela do navegador ----------
    
    if (g_CicloEmExecucao) {
        MsgBox("Já tem um lote rodando (FAPS ou e-Social) — espere terminar (ou aperte Esc pra abortar) antes de iniciar outro.", "Aviso", 48)
        return
    }
    g_CicloEmExecucao := true

    Try {
        ; Consome a flag (zera na hora) — só ESTA chamada de Iniciar() deve
        ; pausar automaticamente;
        iniciouPausado := g_AutoPausarAoIniciar
        g_AutoPausarAoIniciar := false

        if (Trim(caminhoDownload) = "") {
            MsgBox("Defina a pasta de destino na interface antes de iniciar.", "Aviso", 48)
            return
        }
        if !DirExist(caminhoDownload)
            DirCreate(caminhoDownload)

        if !DetectarNavegador() {
            MsgBox("Não encontrei uma janela do Chrome nem do Firefox rodando o sistema.`nAbra o navegador com a página certa antes de iniciar.", "Aviso", 48)
            return
        }

        if (iniciouPausado) {
            ; DefinirPausado (em Interface.ahk) também sincroniza o botão
            ; "Pausar/Retomar" e o texto de Status.
            DefinirPausado(true)
            TrayTip("AutoHotkey", "Script reiniciado. Pressione F1 para DESPAUSAR e iniciar.", 1)
            VerificarControles() ; bloqueia aqui (via g_Pausado) até F1 ser apertado
        }

        WinActivate(janelaAlvo)
        AguardarJanelaAtiva(janelaAlvo, 3)

        if !FileExist(logFile)
            FileAppend("Ciclo;Motivo`n", logFile)

        if !FileExist(logAcoes)
            FileAppend("Timestamp;Ciclo;Etapa;DuracaoMs;LimiteMs;Lento;Status;Detalhes`n", logAcoes)

        ano    := Integer(SubStr(data1, 1, 4))
        mes    := Integer(SubStr(data1, 5, 2))
        anoFim := Integer(SubStr(data2, 1, 4))
        mesFim := Integer(SubStr(data2, 5, 2))

        Loop {
            if (ano < anoFim) || (ano = anoFim && mes < mesFim)
                break

            datainicio := Format("{:02}/{:02}/{:04}", 1, mes, ano)
            datafim    := UltimoDiaDoMes(ano, mes)
            dataTag    := Format("{:04}{:02}", ano, mes)

            ProcessarCiclo(datainicio, datafim, dataTag, prefix, logFile)

            mes--
            if (mes < 1) {
                mes := 12
                ano--
            }
        }

        MsgBox("Processo finalizado.`nVerifique " . logFile . " para ciclos com erro.", "Concluído", 64)
    } Finally {
        g_CicloEmExecucao := false
    }
}