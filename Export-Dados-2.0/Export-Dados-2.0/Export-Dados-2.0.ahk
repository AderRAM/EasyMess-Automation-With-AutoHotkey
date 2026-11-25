; =====================================================================
; Export-Dados-2.0.ahk  (AutoHotkey v2)
; Exportador automático — percorre um intervalo de meses (de data1 até
; data2) exportando um relatório por mês via navegação por busca (Ctrl+F)
; + Tab, com verificação de página real em vez de sleeps fixos. Cobre 2
; fluxos (abas separadas no painel — ver Interface.ahk): FAPS (original)
; e e-Social (Consultas Dinâmicas → Consulta Eventos, 4 portais).
;
; Organizado em módulos (pasta "modulos") pra não ter tudo num arquivo só
; de 1000+ linhas:
;   - modulos\Utilitarios.ahk  -> funções genéricas/compartilhadas
;   - modulos\Pagina1.ahk      -> Filtros Gerais (Referência, datas,
;                                 Executar, caixas Conta/Tipo Folha)
;   - modulos\Pagina2.ahk      -> resultados, exportar PDF/CSV, salvar
;   - modulos\EntrePaginas.ahk -> orquestra um ciclo (chama Pagina1 e
;                                 depois Pagina2 em sequência) — fluxo FAPS
;   - modulos\ESocial.ahk      -> equivalente ao EntrePaginas.ahk, só que
;                                 pro fluxo e-Social (aba separada — Conta
;                                 reaplicada a cada ciclo, pasta por mês)
;   - modulos\Interface.ahk    -> painel de controle (Gui com abas "FAPS"
;                                 e "e-Social")
;
; Este arquivo principal tem: config (inclui os códigos de Conta do
; e-Social — ver ESOCIAL_CONTA_*), os #Include dos módulos, hotkeys e a
; função Iniciar() (o loop que percorre os meses, fluxo FAPS — o
; equivalente do e-Social é IniciarESocial(), em ESocial.ahk).
; =====================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
SetTitleMatchMode(2)
SetKeyDelay(40, 40)   ; delay entre teclas do Send — ajuste se o app for lento

#Include modulos\Utilitarios.ahk
#Include modulos\Pagina1.ahk
#Include modulos\Pagina2.ahk
#Include modulos\EntrePaginas.ahk
#Include modulos\ESocial.ahk
#Include modulos\Interface.ahk

; ============================ CONFIGURAÇÕES ============================
data1   := "202607"          ; AAAAMM — mês mais recente (início do processamento)
data2   := "202304"          ; AAAAMM — mês mais antigo (fim do processamento)

; entidade: definido pelo usuario na interface (painel de controle), a cada
; uso (ex.: "IPAM", "CAMARA", etc — varia conforme o orgao sendo auditado).
; Fica separado do sufixo de classe (que so tem os codigos de conta) — o
; prefixo final do arquivo é montado juntando os dois (ver InserirContas, em
; Pagina1.ahk). Sem valor padrão fixo aqui — CarregarConfiguracoes() (em
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

; --- Tipo da folha (usadas pelo dropdown "Tipo de Folha" + botão "Aplicar
; Tipo Folha" na interface — ver Interface.ahk) ---
; Não afeta o prefixo do nome de arquivo, só o filtro "Tipo Folha" na página.
; Também usada pela aba e-Social (mesmos códigos, confirma o "Manual -
; Exportação e-social - folha de pagamento.doc": IPAM/Prefeitura/Câmara =
; TIPO_FOLHA_NORMAL, Inativos e Pensionistas = TIPO_FOLHA_INATIVOS).
TIPO_FOLHA_NORMAL       := ["1", "12", "16", "22", "4"]  ; IPAM, Prefeitura, Câmara, FAS
TIPO_FOLHA_PENSIONISTAS := ["2", "10", "32", "33"]
TIPO_FOLHA_INATIVOS     := ["1", "9", "22", "23"]

; ==================== e-SOCIAL — CÓDIGOS DE CONTA (por entidade) ====================
; Fonte: "Manual - Exportação e-social - folha de pagamento.doc" (tabela de
; Conta), com a semântica confirmada pelo usuário:
;   - Coluna "Código" (base) = valor usado pela PREFEITURA (a tabela não
;     tem coluna própria pra Prefeitura — ela usa sempre o base).
;   - Célula de SAMAE/IPAM/Câmara/Inativos-Pensionistas com um NÚMERO =
;     SUBSTITUI o código base só pra essa entidade (nunca os dois juntos).
;   - Célula com "Não existe..." = evento excluído pra essa entidade.
;   - Célula em branco = usa o código base normalmente.
;   - SAMAE é uma entidade à parte (sem portal e-Social mapeado ainda) —
;     não entra em nenhuma lista abaixo.
; As 4 listas já refletem os overrides/exclusões linha a linha da tabela
; (não precisa reconsultar o manual pra saber qual código veio de onde).
;
; O evento "IPAM Saúde - Férias Jan à Dezembro" NÃO é um código fixo — é
; 8400+mês (jan=8401 ... dez=8412), só pra Prefeitura/IPAM/Câmara (não
; existe pra Inativos e Pensionistas) — por isso NÃO está nas listas
; abaixo; é calculado e adicionado na hora por ObterContaESocial(), com
; base no mês da Referência sendo exportada naquele ciclo.
ESOCIAL_CONTA_PREFEITURA := ["476", "545", "478", "485", "398", "746", "747", "722", "542", "845", "873", "546", "547", "851", "543", "852", "848", "541", "872", "849", "838", "853", "484", "739", "840"]
ESOCIAL_CONTA_IPAM       := ["476", "544", "478", "485", "398", "746", "747", "722", "542", "845", "873", "546", "851", "543", "852", "848", "541", "872", "849", "853", "484", "739", "840"]
ESOCIAL_CONTA_CAMARA     := ["476", "545", "478", "485", "398", "746", "747", "722", "542", "845", "851", "543", "852", "848", "541", "849", "853", "484", "739", "840"]
ESOCIAL_CONTA_INATIVOS_PENSIONISTAS := ["476", "545", "478", "485", "398", "746", "747", "722", "7849", "7852", "542", "845", "7846", "7851", "7850", "851", "7851", "852", "848", "541", "7845", "849", "853", "484", "739", "840"]

; Código do evento "IPAM Saúde - Férias" pro mês informado (1=janeiro ...
; 12=dezembro) — confirmado pelo usuário: código = 8400 + número do mês
; (ex.: julho = 8407). Só se aplica a Prefeitura/IPAM/Câmara — ver
; ObterContaESocial, que não chama isso pra Inativos e Pensionistas.
CodigoFeriasIPAMSaude(mes) {
    return String(8400 + Integer(mes))
}

; Monta a lista completa de códigos de Conta do e-Social pra uma entidade e
; mês específicos — junta a lista fixa (ESOCIAL_CONTA_*) com o código
; mensal de férias do IPAM Saúde quando aplicável. nomeEntidade: uma de
; "PREFEITURA", "IPAM", "CAMARA", "INATIVOS_PENSIONISTAS".
ObterContaESocial(nomeEntidade, mes) {
    global ESOCIAL_CONTA_PREFEITURA, ESOCIAL_CONTA_IPAM, ESOCIAL_CONTA_CAMARA, ESOCIAL_CONTA_INATIVOS_PENSIONISTAS

    switch nomeEntidade {
        case "PREFEITURA":
            base := ESOCIAL_CONTA_PREFEITURA
        case "IPAM":
            base := ESOCIAL_CONTA_IPAM
        case "CAMARA":
            base := ESOCIAL_CONTA_CAMARA
        case "INATIVOS_PENSIONISTAS":
            ; Não usa o código mensal de férias do IPAM Saúde — ver
            ; comentário junto de ESOCIAL_CONTA_* acima ("Não existe nos
            ; INATIVOS E PENSIONISTAS").
            return ESOCIAL_CONTA_INATIVOS_PENSIONISTAS.Clone()
        default:
            return []
    }

    lista := base.Clone()
    lista.Push(CodigoFeriasIPAMSaude(mes))
    return lista
}

; Caminho onde os arquivos exportados devem ser salvos (sem barra no final).
; Sem valor padrão fixo aqui — definido pelo usuario na interface ("Pasta de
; destino") e lembrado entre execuções via config_v3.ini (ver Interface.ahk).
caminhoDownload := ""

; --- e-Social (aba separada — ver modulos/ESocial.ahk) ---
; data1ES/data2ES: mesma ideia de data1/data2 acima, mas independentes (o
; lote e-Social pode cobrir um intervalo de meses diferente do FAPS).
; pastaBaseES: SÓ a pasta raiz (ex.: "A:\...\ARQUIVOS ESOCIAL\Exportados")
; — IniciarESocial monta a subpasta "MMAAAA\CONSULTA EVENTOS" por ciclo
; sozinho (ver PastaCicloESocial, em ESocial.ahk). Sem valores padrão fixos
; aqui — CarregarConfiguracoes() (Interface.ahk) recupera os últimos
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
LIMITE_ACAO_LENTA_MS := 3000

; Teto máximo (segundos) pra esperar enquanto a página estiver no estado
; "CARREGANDO" (consulta processando no servidor após clicar "Executar" —
; ver DetectarPagina/AguardarPagina, em Utilitarios.ahk). Bem mais generoso
; que os timeouts normais de página (poucos segundos) de propósito: só
; existe pra evitar travar pra sempre se a tela realmente ficar presa
; nesse estado — enquanto "CARREGANDO" for detectado de verdade a cada
; checagem, o script continua esperando normalmente.
TIMEOUT_MAX_CARREGANDO_SEGUNDOS := 60

; --- Estado interno usado para medir tempo entre ações e identificar o
; ciclo atual nos logs (não editar) ---
g_CicloAtual     := "-"
g_UltimoTickAcao := 0
g_Pausado        := false
g_PedidoReset    := false

; true só na primeira chamada de Iniciar() depois de um F3 (Reset) — ver
; ResetarScript()/Iniciar() mais abaixo. Calculado uma única vez aqui (a
; partir do argumento "/restarted" passado pelo próprio ResetarScript() ao
; relançar o script) porque A_Args não muda durante a vida do processo: se
; Iniciar() checasse A_Args diretamente toda vez que fosse chamada, TODA
; execução (F1/Executar) dali em diante — não só a primeira depois do
; restart — forçaria uma pausa automática, mesmo sem relação nenhuma com o
; restart. Iniciar() consome (zera) esta flag após usá-la uma vez.
g_AutoPausarAoIniciar := (A_Args.Length > 0 && A_Args[1] = "/restarted")

; --- Contagem de Tabs a partir do texto localizado via Ctrl+F ---
; Ctrl+F + Enter + 1 Shift+Tab já fecha a busca e deixa o foco EM CIMA do
; elemento encontrado. Depende do layout de cada elemento se são
; necessários Tabs extras (e, para "Referência", um Enter extra — veja
; ativarComEnter em LocalizarEFocar, em Utilitarios.ahk) para chegar no
; alvo real.
TABS_APOS_REFERENCIA := 1   ; sequencia confirmada: Shift+Tab, Enter (ativa o rotulo), Tab 1x -> campo de data
TABS_ENTRE_CAMPOS    := 2   ; Tabs entre o campo de data e o próximo campo relevante
TABS_APOS_EXECUTAR   := 0   ; botão: 0 Tabs extras
TABS_APOS_VOLTAR     := 0   ; botão: 0 Tabs extras
; "Exportar em PDF" nao usa esse mecanismo — Ctrl+F + 3 Tabs direto no
; módulo Pagina2.ahk, entao nao ha uma variavel de Tabs extras para ele aqui.

; Nome da janela/aba do navegador onde o processo roda.
janelaAlvo := "ahk_exe chrome.exe"

; ======================== INTERFACE (painel de controle) ================
; Carrega valores salvos de uma execução anterior (config_v3.ini) por cima
; dos valores padrão acima, e então monta a janela — ver Interface.ahk.
CarregarConfiguracoes()
CriarInterface()

; ============================== HOTKEYS =================================
; F1   -> inicia o processo (dê foco na janela correta ANTES de apertar)
; F2   -> pausa/retoma
; Esc  -> aborta o script imediatamente
; F3   -> reseta o script (recarrega as variáveis e reinicia sem fechar)

; F2/F3/Esc aqui são só o caminho "rápido" (funciona quando o script está
; ocioso). O caminho CONFIÁVEL, que funciona mesmo com um ciclo rodando, é
; VerificarControles() (em Utilitarios.ahk) — chamado o tempo todo de
; dentro do ciclo (ver RegistrarEvento/AguardarPagina) e que lê o estado
; físico da tecla direto, sem depender do hook de hotkeys.
F1:: ExecutarProcessamento() ; em Interface.ahk — sincroniza os campos da interface (incl. Entidade) e salva a config antes de iniciar, igual ao botão "Executar"
F2:: AlternarPausa() ; em Interface.ahk — mantém o botão "Pausar/Retomar" sincronizado
Esc:: ExitApp()
F3:: ResetarScript()
; Conta/Tipo Folha (antes hotkeys F4-F9) agora só são acionados pelos
; botões "Aplicar Conta"/"Aplicar Tipo Folha" na interface (Interface.ahk)
; — ver AplicarConta/AplicarTipoFolha lá.

; //Função de reset
ResetarScript() {
    TrayTip("AutoHotkey", "Resetando... O script reiniciará PAUSADO.", 1)
    Sleep(500)
    Run('"' . A_AhkPath . '" /restart "' . A_ScriptFullPath . '" /restarted')
}

; ============================ FUNÇÃO PRINCIPAL ==========================
Iniciar() {
    global data1, data2, prefix, logFile, logAcoes, janelaAlvo, caminhoDownload
    global g_AutoPausarAoIniciar

    ; Consome a flag (zera na hora) — só ESTA chamada de Iniciar() deve
    ; pausar automaticamente; ver comentário junto da declaração da flag,
    ; no topo do arquivo.
    iniciouPausado := g_AutoPausarAoIniciar
    g_AutoPausarAoIniciar := false

    if (Trim(caminhoDownload) = "") {
        MsgBox("Defina a pasta de destino na interface antes de iniciar.", "Aviso", 48)
        return
    }
    if !DirExist(caminhoDownload)
        DirCreate(caminhoDownload)

    if !WinExist(janelaAlvo) {
        MsgBox("Não encontrei a janela alvo (" . janelaAlvo . ").`nAjuste a variável janelaAlvo no topo do script.", "Aviso", 48)
        return
    }

    if (iniciouPausado) {
        ; DefinirPausado (em Interface.ahk) também sincroniza o botão
        ; "Pausar/Retomar" e o texto de Status — setar g_Pausado direto
        ; aqui (como antes) deixava a interface mostrando "Rodando..." /
        ; botão "Pausar" mesmo com o script de fato bloqueado esperando F2.
        DefinirPausado(true)
        TrayTip("AutoHotkey", "Script reiniciado. Pressione F2 para DESPAUSAR e iniciar.", 1)
        VerificarControles() ; bloqueia aqui (via g_Pausado) até F2 ser apertado
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
}