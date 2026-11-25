; =====================================================================
; Interface.ahk
; Painel de controle: permite configurar todos os dados necessários
; (datas, entidade, pasta de destino, classe de conta, tipo de folha),
; lembra os valores entre execuções (arquivo config_v3.ini, na mesma
; pasta do script) e permite Executar/Pausar-Retomar/Resetar por botão.
; Os hotkeys F1-F3/Esc continuam funcionando normalmente — a interface é um
; caminho adicional pra eles, não substitui o teclado. Conta/Tipo Folha,
; porém, só são acionados por aqui (botões "Aplicar Conta"/"Aplicar Tipo
; Folha") — não têm mais hotkey dedicado.
; =====================================================================

ARQUIVO_CONFIG_INTERFACE := A_ScriptDir . "\config_v3.ini"
MAX_ENTIDADES_HISTORICO  := 15
MAX_CLASSES_HISTORICO    := 15

; Lista inicial de entidades conhecidas (orgãos tipicamente auditados —
; mesmos citados nos comentários de TIPO_FOLHA_NORMAL/entidade acima).
; Aparece no combo mesmo numa instalação nova, antes de qualquer uso real;
; entidades digitadas pelo usuario continuam tendo prioridade (aparecem
; primeiro na lista — ver CarregarHistoricoEntidades).
ENTIDADES_PADRAO := ["IPAM", "Prefeitura", "Câmara", "FAS", "Pensionistas", "Inativos"]

; Lista fixa de classes pré-definidas (sempre presentes no combo, mesmo numa
; instalação nova) — mesmo texto usado antes como itens fixos do dropdown
; "Classe de Conta". Conjuntos de códigos avulsos digitados pelo usuario
; entram no histórico e aparecem ACIMA destas (mais recente primeiro — ver
; CarregarHistoricoClasses).
CLASSES_PADRAO := [
    "(nenhuma)",
    "A - 874/875/876/877/878/879",
    "S - BASE (9081/9084/9086/9089/9091/9094)",
    "D - PATRONAL (9085/9082/9087/9090/9095/9092)",
    "RPC - Previdência Complementar (conforme Entidade)"
]

g_Gui := ""

; Guarda a posição/tamanho originais dos controles "esticáveis" e o tamanho
; original da janela, pra GuiRedimensionar() saber quanto crescer cada um
; quando a janela é redimensionada (ver seção RESIZE mais abaixo).
g_PosOriginal  := Map()
g_LarguraBase  := 0
g_AlturaBase   := 0

; ---------- Carrega valores salvos (se existirem) nas variáveis globais ----------
; Chamada ANTES de CriarInterface(), pra os campos já nascerem preenchidos
; com o último valor usado.
CarregarConfiguracoes() {
    global data1, data2, entidade, caminhoDownload, ARQUIVO_CONFIG_INTERFACE
    global data1ES, data2ES, pastaBaseES

    if !FileExist(ARQUIVO_CONFIG_INTERFACE)
        return

    valor := IniRead(ARQUIVO_CONFIG_INTERFACE, "Config", "Data1", "")
    if (valor != "")
        data1 := valor

    valor := IniRead(ARQUIVO_CONFIG_INTERFACE, "Config", "Data2", "")
    if (valor != "")
        data2 := valor

    valor := IniRead(ARQUIVO_CONFIG_INTERFACE, "Config", "Entidade", "")
    if (valor != "")
        entidade := valor

    valor := IniRead(ARQUIVO_CONFIG_INTERFACE, "Config", "CaminhoDownload", "")
    if (valor != "")
        caminhoDownload := valor

    ; ---- e-Social (aba separada — ver modulos/ESocial.ahk) ----
    valor := IniRead(ARQUIVO_CONFIG_INTERFACE, "ConfigES", "Data1ES", "")
    if (valor != "")
        data1ES := valor

    valor := IniRead(ARQUIVO_CONFIG_INTERFACE, "ConfigES", "Data2ES", "")
    if (valor != "")
        data2ES := valor

    valor := IniRead(ARQUIVO_CONFIG_INTERFACE, "ConfigES", "PastaBaseES", "")
    if (valor != "")
        pastaBaseES := valor
}

; ---------- Histórico de entidades já usadas (alimenta o combo) ----------

; Retorna o histórico salvo (usadas mais recentemente primeiro) seguido de
; qualquer entidade padrão (ENTIDADES_PADRAO) que ainda não apareça nele —
; assim o combo nunca fica vazio, mesmo antes do primeiro uso real.
CarregarHistoricoEntidades() {
    global ARQUIVO_CONFIG_INTERFACE, ENTIDADES_PADRAO

    lista := []
    bruto := IniRead(ARQUIVO_CONFIG_INTERFACE, "Entidades", "Lista", "")
    for item in StrSplit(bruto, "|") {
        item := Trim(item)
        if (item != "")
            lista.Push(item)
    }

    for padrao in ENTIDADES_PADRAO {
        jaExiste := false
        for item in lista {
            if (StrLower(item) = StrLower(padrao)) {
                jaExiste := true
                break
            }
        }
        if !jaExiste
            lista.Push(padrao)
    }

    return lista
}

SalvarHistoricoEntidades(lista) {
    global ARQUIVO_CONFIG_INTERFACE
    IniWrite(JuntarLista(lista, "|"), ARQUIVO_CONFIG_INTERFACE, "Entidades", "Lista")
}

; Coloca novaEntidade no topo do histórico (sem duplicar, comparação sem
; diferenciar maiúsculas/minúsculas), limita o tamanho da lista e grava.
; Retorna a lista atualizada, ou "" se não houver nada pra atualizar.
AtualizarHistoricoEntidades(novaEntidade) {
    global MAX_ENTIDADES_HISTORICO

    novaEntidade := Trim(StrReplace(novaEntidade, "|", ""))
    if (novaEntidade = "")
        return ""

    listaAtual := CarregarHistoricoEntidades()
    novaLista  := [novaEntidade]
    for item in listaAtual {
        if (StrLower(item) != StrLower(novaEntidade))
            novaLista.Push(item)
    }
    if (novaLista.Length > MAX_ENTIDADES_HISTORICO)
        novaLista.Length := MAX_ENTIDADES_HISTORICO

    SalvarHistoricoEntidades(novaLista)
    return novaLista
}

JuntarLista(lista, separador) {
    resultado := ""
    for indice, item in lista
        resultado .= (indice = 1 ? "" : separador) . item
    return resultado
}

; Reconstrói os itens do combo de entidade (preservando o texto digitado
; no momento) — chamada depois que o histórico muda, pra entidade nova
; aparecer na lista já na mesma sessão, sem precisar reabrir a interface.
AtualizarListaComboEntidade(lista) {
    global g_Gui

    if !IsObject(g_Gui) || !IsObject(lista)
        return

    textoAtual := g_Gui["CampoEntidade"].Text
    g_Gui["CampoEntidade"].Delete()
    if (lista.Length > 0)
        g_Gui["CampoEntidade"].Add(lista)
    g_Gui["CampoEntidade"].Text := textoAtual
}

; ---------- Histórico de classes de conta já usadas (alimenta o combo) ----------
; Mesmo mecanismo do histórico de Entidade acima, mas pra "Classe de Conta":
; guarda conjuntos de códigos avulsos digitados pelo usuario (ex.: "100, 200,
; 300") pra poder reescolher depois, em vez de só lembrar o último (ver
; DividirCodigos/AplicarConta). As 5 classes fixas (CLASSES_PADRAO) sempre
; aparecem também, preenchendo o combo mesmo numa instalação nova.
CarregarHistoricoClasses() {
    global ARQUIVO_CONFIG_INTERFACE, CLASSES_PADRAO

    lista := []
    bruto := IniRead(ARQUIVO_CONFIG_INTERFACE, "Classes", "Lista", "")
    for item in StrSplit(bruto, "|") {
        item := Trim(item)
        if (item != "")
            lista.Push(item)
    }

    for padrao in CLASSES_PADRAO {
        jaExiste := false
        for item in lista {
            if (StrLower(item) = StrLower(padrao)) {
                jaExiste := true
                break
            }
        }
        if !jaExiste
            lista.Push(padrao)
    }

    return lista
}

SalvarHistoricoClasses(lista) {
    global ARQUIVO_CONFIG_INTERFACE
    IniWrite(JuntarLista(lista, "|"), ARQUIVO_CONFIG_INTERFACE, "Classes", "Lista")
}

; Coloca novaClasse no topo do histórico (sem duplicar, comparação sem
; diferenciar maiúsculas/minúsculas), limita o tamanho da lista e grava.
; Retorna a lista atualizada, ou "" se não houver nada pra atualizar.
; "(nenhuma)" não é salva — ela é só o placeholder de "sem classe aplicada",
; promovê-la pro topo do histórico toda vez que ficasse selecionada só
; atrapalharia (empurraria pra baixo classes/códigos de verdade já usados).
AtualizarHistoricoClasses(novaClasse) {
    global MAX_CLASSES_HISTORICO

    novaClasse := Trim(StrReplace(novaClasse, "|", ""))
    if (novaClasse = "" || novaClasse = "(nenhuma)")
        return ""

    listaAtual := CarregarHistoricoClasses()
    novaLista  := [novaClasse]
    for item in listaAtual {
        if (StrLower(item) != StrLower(novaClasse))
            novaLista.Push(item)
    }
    if (novaLista.Length > MAX_CLASSES_HISTORICO)
        novaLista.Length := MAX_CLASSES_HISTORICO

    SalvarHistoricoClasses(novaLista)
    return novaLista
}

; Reconstrói os itens do combo de classe (preservando o texto digitado no
; momento) — chamada depois que o histórico muda, pra um código avulso novo
; aparecer na lista já na mesma sessão, sem precisar reabrir a interface.
AtualizarListaComboClasse(lista) {
    global g_Gui

    if !IsObject(g_Gui) || !IsObject(lista)
        return

    textoAtual := g_Gui["CampoClasse"].Text
    g_Gui["CampoClasse"].Delete()
    if (lista.Length > 0)
        g_Gui["CampoClasse"].Add(lista)
    g_Gui["CampoClasse"].Text := textoAtual
}

; ---------- Salva os valores atuais dos campos da interface em disco ----------
SalvarConfiguracoes() {
    global g_Gui, ARQUIVO_CONFIG_INTERFACE

    if !IsObject(g_Gui)
        return

    entidadeAtual := g_Gui["CampoEntidade"].Text
    classeAtual   := g_Gui["CampoClasse"].Text

    IniWrite(g_Gui["CampoData1"].Value, ARQUIVO_CONFIG_INTERFACE, "Config", "Data1")
    IniWrite(g_Gui["CampoData2"].Value, ARQUIVO_CONFIG_INTERFACE, "Config", "Data2")
    IniWrite(entidadeAtual, ARQUIVO_CONFIG_INTERFACE, "Config", "Entidade")
    IniWrite(g_Gui["CampoPasta"].Value, ARQUIVO_CONFIG_INTERFACE, "Config", "CaminhoDownload")
    IniWrite(classeAtual, ARQUIVO_CONFIG_INTERFACE, "Config", "Classe")
    IniWrite(g_Gui["CampoTipoFolha"].Text, ARQUIVO_CONFIG_INTERFACE, "Config", "TipoFolha")

    ; ---- e-Social ----
    IniWrite(g_Gui["CampoData1ES"].Value, ARQUIVO_CONFIG_INTERFACE, "ConfigES", "Data1ES")
    IniWrite(g_Gui["CampoData2ES"].Value, ARQUIVO_CONFIG_INTERFACE, "ConfigES", "Data2ES")
    IniWrite(g_Gui["CampoEntidadeES"].Text, ARQUIVO_CONFIG_INTERFACE, "ConfigES", "EntidadeES")
    IniWrite(g_Gui["CampoTipoFolhaES"].Text, ARQUIVO_CONFIG_INTERFACE, "ConfigES", "TipoFolhaES")
    IniWrite(g_Gui["CampoPastaES"].Value, ARQUIVO_CONFIG_INTERFACE, "ConfigES", "PastaBaseES")

    novaListaEntidade := AtualizarHistoricoEntidades(entidadeAtual)
    if IsObject(novaListaEntidade)
        AtualizarListaComboEntidade(novaListaEntidade)

    novaListaClasse := AtualizarHistoricoClasses(classeAtual)
    if IsObject(novaListaClasse)
        AtualizarListaComboClasse(novaListaClasse)
}

; ---------- Monta a janela ----------
CriarInterface() {
    global g_Gui, data1, data2, entidade, caminhoDownload, ARQUIVO_CONFIG_INTERFACE, g_Pausado
    global g_PosOriginal, g_LarguraBase, g_AlturaBase
    global data1ES, data2ES, pastaBaseES

    g_Gui := Gui("+Resize", "FAPS Export - Painel de Controle")
    g_Gui.SetFont("s10")
    g_Gui.MarginX := 12
    g_Gui.MarginY := 10
    g_Gui.OnEvent("Close", GuiFechar)

    ; ---------- Abas: "FAPS" (painel original, sem mudança de
    ; comportamento) e "e-Social" (exportação Consultas Dinâmicas →
    ; Consulta Eventos pros 4 portais do manual — ver bloco mais abaixo e
    ; modulos/ESocial.ahk). UseTab(n) associa os controles adicionados A
    ; SEGUIR à aba n; UseTab()
    ; sem argumento (mais abaixo) encerra essa associação. w/h abaixo foram
    ; estimados a partir do conteúdo atual da aba FAPS — ajustar rodando o
    ; script e conferindo visualmente se sobra/falta espaço.
    ; w680 (não w580): a linha mais larga do conteúdo (Pasta de destino +
    ; campo w370 + botão "Procurar..." + botão "◀") termina em ~664px a
    ; partir da margem da janela — e como o conteúdo da aba começa 12px
    ; recuado em relação à própria aba (ver "xp+12" logo abaixo), a aba
    ; precisa de uns 670-680px pra caber a linha inteira sem cortar o
    ; "Procurar..." — confirmado visualmente pelo usuário que 580 cortava.
    abas := g_Gui.AddTab3("vAbaPainel w680 h480", ["FAPS", "e-Social"])
    abas.GetPos(&abaX, &abaY) ; guarda a posição do próprio controle de abas
                              ; — "xp/yp" só enxergam o ÚLTIMO controle
                              ; adicionado, então não dá pra usar isso pra
                              ; posicionar o conteúdo da aba 2 (que vem
                              ; depois de vários outros controles da aba 1)
    abas.UseTab(1)

    ; Campo continua aceitando "AAAAMM" digitado direto (ex.: 202607) — o
    ; botão "Calendário..." é só um atalho opcional que abre um mini
    ; calendário (ver AbrirCalendario mais abaixo) e preenche o campo com
    ; o mês/ano escolhido, sem travar o formato de exibição nem impedir
    ; digitação manual.
    ; "Section" aqui marca essa posição (deslocada pra caber dentro da aba,
    ; abaixo do cabeçalho) como a nova referência pra "xs"/novo-linha
    ; implícito — SEM isso, os controles das linhas seguintes que usam
    ; "xm" (que sempre volta pra margem da JANELA, não da aba) calculavam a
    ; posição Y como se estivessem fora da aba, ficando cravados perto do
    ; topo da janela e "sumindo" atrás do cabeçalho das abas — confirmado
    ; visualmente (só a 1ª linha aparecia). Por isso as linhas seguintes
    ; deste bloco agora usam "xs" (início da seção) em vez de "xm".
    g_Gui.AddText("xp+12 yp+35 w150 Section", "Data início (AAAAMM):")
    g_Gui.AddEdit("vCampoData1 w150 x+10 yp-3", data1)
    g_Gui.AddButton("x+5 yp-3 w90", "Calendário...").OnEvent("Click", (*) => AbrirCalendario("CampoData1"))

    g_Gui.AddText("w150 xs", "Data fim (AAAAMM):")
    g_Gui.AddEdit("vCampoData2 w150 x+10 yp-3", data2)
    g_Gui.AddButton("x+5 yp-3 w90", "Calendário...").OnEvent("Click", (*) => AbrirCalendario("CampoData2"))

    ; Entidade: ComboBox editável (permite digitar uma entidade nova OU
    ; escolher uma já usada antes na seta à direita — histórico gravado em
    ; config_v3.ini, ver CarregarHistoricoEntidades acima).
    g_Gui.AddText("w150 xs", "Entidade:")
    g_Gui.AddComboBox("vCampoEntidade w250 x+10 yp-3", CarregarHistoricoEntidades())
    g_Gui["CampoEntidade"].Text := entidade

    g_Gui.AddText("w150 xs", "Pasta de destino:")
    g_Gui.AddEdit("vCampoPasta w370 x+10 yp-3", caminhoDownload)
    g_Gui.AddButton("vBotaoProcurar x+5 yp-3 w70", "Procurar...").OnEvent("Click", EscolherPasta)
    ; Sobe um nível a partir da pasta atual no campo (ex.: "...\CONSULTA_EVENTOS\FAPSPENS" -> "...\CONSULTA_EVENTOS") — atalho pra quando só o nome da última subpasta muda entre exportações (ver SubirPasta mais abaixo).
    g_Gui.AddButton("vBotaoSubirPasta x+5 yp-3 w30", "◀").OnEvent("Click", SubirPasta)

    g_Gui.AddText("w150 xs", "Tipo de Folha:")
    g_Gui.AddDropDownList("vCampoTipoFolha w440 x+10 yp-3", [
        "(nenhum)",
        "Normal (IPAM/Prefeitura/Câmara/FAS)",
        "Pensionistas",
        "Inativos"
    ])
    ; Classe de Conta: ComboBox editável — permite tanto escolher uma das
    ; classes pré-definidas/já usadas (seta à direita) quanto digitar
    ; códigos de conta avulsos pra essa exportação específica (ex.: "100,
    ; 200, 300"), pra quando nenhuma das classes prontas serve. Ver
    ; AplicarConta, que distingue os casos, e DividirCodigos
    ; (Utilitarios.ahk), que lê qualquer sequência de dígitos do texto
    ; digitado, aceitando vírgula, espaço ou qualquer outro separador. Cada
    ; conjunto de códigos avulsos digitado fica salvo num histórico (igual
    ; já acontece com Entidade — ver CarregarHistoricoClasses) em vez de só
    ; lembrar o último usado.
    g_Gui.AddText("w150 xs", "Classe de Conta:")
    g_Gui.AddComboBox("vCampoClasse w440 x+10 yp-3", CarregarHistoricoClasses())
    g_Gui.AddText("vTextoAvisoClasse xs y+2 w440 cGray", "Ou digite códigos avulsos separados por vírgula/espaço (ex.: 100, 200, 300). RPC exige Entidade = Prefeitura, FAS ou Câmara")

    ; Restaura a classe/tipo de folha salvos da última vez. CampoClasse usa
    ; .Text (não .Choose) porque o valor salvo pode ser um código avulso
    ; digitado, que não é nenhum item da lista — .Choose só funcionaria
    ; pras classes pré-definidas.
    g_Gui["CampoClasse"].Text := IniRead(ARQUIVO_CONFIG_INTERFACE, "Config", "Classe", "(nenhuma)")

    try g_Gui["CampoTipoFolha"].Choose(IniRead(ARQUIVO_CONFIG_INTERFACE, "Config", "TipoFolha", "(nenhum)"))
    catch
        g_Gui["CampoTipoFolha"].Choose(1)

    ; Botões separados (em vez de um único "Aplicar Conta/Tipo Folha") —
    ; aplicar os dois campos numa mesma ação encadeada os deixava
    ; suscetíveis a interferência cruzada (a busca/limpeza de um campo
    ; podia mirar/mexer no outro, já que os dois vivem na mesma página).
    g_Gui.AddButton("vBotaoAplicarTipoFolha xs w250 y+15", "Aplicar Tipo Folha na página").OnEvent("Click", AplicarTipoFolha)
    g_Gui.AddButton("vBotaoAplicarConta x+10 w250", "Aplicar Conta na página").OnEvent("Click", AplicarConta)

    g_Gui.AddText("vTextoStatus xs w520 y+20 cBlue", "Status: Pronto")

    g_Gui.AddButton("vBotaoExecutar xs w170 y+10", "Executar").OnEvent("Click", BotaoExecutar)
    g_Gui.AddButton("vBotaoPausar x+10 w170", g_Pausado ? "Retomar" : "Pausar").OnEvent("Click", BotaoPausar)
    g_Gui.AddButton("vBotaoResetar x+10 w170", "Resetar").OnEvent("Click", BotaoResetar)

    g_Gui.AddText("vTextoHotkeys xs y+15 w520 cGray", "Hotkeys continuam ativos: F1 Executar | F2 Pausar/Retomar | F3 Resetar | Esc Sair")

    ; ---------- Aba "e-Social" ----------
    ; Reaproveita os MESMOS mecanismos do FAPS onde possível: AbrirCalendario
    ; (parametrizado por nome de campo), InserirTipoFolha/TIPO_FOLHA_* (via
    ; AplicarTipoFolhaComTexto, compartilhado com AplicarTipoFolha), e os
    ; handlers de pausa/reset (BotaoPausar/BotaoResetar não são específicos
    ; de aba). Só "Entidade" é diferente do FAPS: aqui é uma lista FIXA
    ; (DropDownList, não ComboBox editável) com só os 4 portais do manual —
    ; cada um tem sua própria lista de códigos de Conta (ESOCIAL_CONTA_*,
    ; ver Export-Dados-2.0.ahk) e nome de pasta/arquivo fixos, então não faz
    ; sentido aceitar texto livre aqui como o campo Entidade do FAPS aceita.
    ; Não tem botão "Aplicar Conta": a Conta é calculada e reaplicada
    ; SOZINHA a cada mês do lote (ver ProcessarCicloESocial, em
    ; ESocial.ahk) porque um dos códigos muda por mês.
    abas.UseTab(2)
    g_Gui.AddText("x" . (abaX + 12) . " y" . (abaY + 35) . " w150 Section", "Data início (AAAAMM):")
    g_Gui.AddEdit("vCampoData1ES w150 x+10 yp-3", data1ES)
    g_Gui.AddButton("x+5 yp-3 w90", "Calendário...").OnEvent("Click", (*) => AbrirCalendario("CampoData1ES"))

    g_Gui.AddText("w150 xs", "Data fim (AAAAMM):")
    g_Gui.AddEdit("vCampoData2ES w150 x+10 yp-3", data2ES)
    g_Gui.AddButton("x+5 yp-3 w90", "Calendário...").OnEvent("Click", (*) => AbrirCalendario("CampoData2ES"))

    g_Gui.AddText("w150 xs", "Entidade:")
    g_Gui.AddDropDownList("vCampoEntidadeES w250 x+10 yp-3", [
        "(nenhuma)",
        "Prefeitura",
        "IPAM",
        "Câmara",
        "Inativos e Pensionistas"
    ])

    g_Gui.AddText("w150 xs", "Tipo de Folha:")
    g_Gui.AddDropDownList("vCampoTipoFolhaES w440 x+10 yp-3", [
        "(nenhum)",
        "Normal (IPAM/Prefeitura/Câmara)",
        "Pensionistas",
        "Inativos"
    ])

    g_Gui.AddText("w150 xs", "Pasta base:")
    g_Gui.AddEdit("vCampoPastaES w370 x+10 yp-3", pastaBaseES)
    g_Gui.AddButton("vBotaoProcurarES x+5 yp-3 w70", "Procurar...").OnEvent("Click", EscolherPastaES)

    ; Restaura Entidade/Tipo de Folha salvos da última vez.
    try g_Gui["CampoEntidadeES"].Choose(IniRead(ARQUIVO_CONFIG_INTERFACE, "ConfigES", "EntidadeES", "(nenhuma)"))
    catch
        g_Gui["CampoEntidadeES"].Choose(1)

    try g_Gui["CampoTipoFolhaES"].Choose(IniRead(ARQUIVO_CONFIG_INTERFACE, "ConfigES", "TipoFolhaES", "(nenhum)"))
    catch
        g_Gui["CampoTipoFolhaES"].Choose(1)

    ; SEM "y+N" aqui de propósito: "Pasta base" (CampoPastaES, logo acima)
    ; pode crescer pra 2-3 linhas visuais conforme o tamanho do caminho
    ; digitado (confirmado pelo usuário — a caixa ficou mais alta que o
    ; botão "Procurar..." previa, e "y+15" relativo ao Procurar não levava
    ; isso em conta, invadindo a linha do botão). Deixando SÓ "xs" (sem y
    ; explícito), o AutoHotkey calcula a posição com base na altura REAL da
    ; linha anterior (mesmo mecanismo que já funciona certo pra "Tipo de
    ; Folha:", logo acima de "Pasta base" — nunca colide mesmo se algum
    ; controle da linha anterior for mais alto que o previsto).
    g_Gui.AddButton("vBotaoAplicarTipoFolhaES xs w250", "Aplicar Tipo Folha na página").OnEvent("Click", AplicarTipoFolhaES)

    g_Gui.AddText("vTextoStatusES xs w520 y+20 cBlue", "Status: Pronto")

    g_Gui.AddButton("vBotaoExecutarES xs w170 y+10", "Executar e-Social").OnEvent("Click", BotaoExecutarES)
    g_Gui.AddButton("vBotaoPausarES x+10 w170", g_Pausado ? "Retomar" : "Pausar").OnEvent("Click", BotaoPausar)
    g_Gui.AddButton("vBotaoResetarES x+10 w170", "Resetar").OnEvent("Click", BotaoResetar)

    abas.UseTab() ; encerra o contexto de aba — nada mais é filho de aba depois disso

    ; ---------- RESIZE: registra os controles que devem esticar/deslocar
    ; quando a janela for redimensionada (ver GuiRedimensionar mais abaixo).
    for nome in ["AbaPainel", "CampoEntidade", "CampoPasta", "BotaoProcurar", "BotaoSubirPasta", "CampoClasse", "TextoAvisoClasse", "CampoTipoFolha", "TextoStatus", "TextoHotkeys",
                 "CampoEntidadeES", "CampoPastaES", "BotaoProcurarES", "CampoTipoFolhaES", "TextoStatusES"]
        RegistrarPosOriginal(nome)

    g_Gui.Show()

    g_Gui.GetClientPos(,, &larguraBase, &alturaBase)
    g_LarguraBase := larguraBase
    g_AlturaBase  := alturaBase
    ; Só faz sentido esticar HORIZONTALMENTE (os campos ficam mais largos) —
    ; é um painel de controle "chapado", sem nada que aproveite altura
    ; extra, então a altura fica travada no tamanho original (senão,
    ; maximizar a janela deixa uma área cinza vazia enorme embaixo).
    g_Gui.Opt("+MinSize" . larguraBase . "x" . alturaBase)
    g_Gui.Opt("+MaxSize100000x" . alturaBase)
    g_Gui.OnEvent("Size", GuiRedimensionar)
}

RegistrarPosOriginal(nome) {
    global g_Gui, g_PosOriginal
    g_Gui[nome].GetPos(&x, &y, &w, &h)
    g_PosOriginal[nome] := {x: x, y: y, w: w, h: h}
}

; Expande os campos de texto/dropdowns horizontalmente junto com a janela
; (e desloca o botão "Procurar..." pra continuar colado na caixa de pasta),
; em vez de deixar tudo cravado no canto superior esquerdo com espaço vazio
; sobrando à direita quando a janela é maximizada/esticada.
GuiRedimensionar(GuiObj, MinMax, Largura, Altura) {
    global g_PosOriginal, g_LarguraBase

    if (MinMax = -1) ; minimizada — nada a fazer
        return
    if (g_LarguraBase = 0)
        return

    deltaW := Largura - g_LarguraBase

    for nome, original in g_PosOriginal {
        if (nome = "BotaoProcurar" || nome = "BotaoSubirPasta" || nome = "BotaoProcurarES") {
            novoX := Max(original.x + deltaW, original.x)
            GuiObj[nome].Move(novoX)
        } else {
            novaLargura := Max(original.w + deltaW, 100)
            GuiObj[nome].Move(,, novaLargura)
        }
    }

    ; Os Text (principalmente o "TextoHotkeys", que quebra em 2 linhas)
    ; deixam pixels "fantasma" da quebra de linha anterior se só a área
    ; nova for repintada — força repintar a janela inteira (com os filhos)
    ; imediatamente pra não sobrar lixo visual depois de redimensionar.
    DllCall("RedrawWindow", "ptr", GuiObj.Hwnd, "ptr", 0, "ptr", 0, "uint", 0x1 | 0x4 | 0x80 | 0x100)
}

; ---------- Handlers dos botões ----------

EscolherPasta(*) {
    global g_Gui
    pasta := DirSelect(g_Gui["CampoPasta"].Value,, "Escolha a pasta de destino")
    if (pasta != "")
        g_Gui["CampoPasta"].Value := pasta
}

; Mesma ideia de EscolherPasta, só que pra pasta BASE do e-Social (a
; subpasta "MMAAAA\CONSULTA EVENTOS" é montada sozinha por ciclo — ver
; PastaCicloESocial, em ESocial.ahk).
EscolherPastaES(*) {
    global g_Gui
    pasta := DirSelect(g_Gui["CampoPastaES"].Value,, "Escolha a pasta base do e-Social")
    if (pasta != "")
        g_Gui["CampoPastaES"].Value := pasta
}

; Botão "▲": sobe um nível a partir da pasta atual no campo (ex.:
; "...\CONSULTA_EVENTOS\FAPSPENS" -> "...\CONSULTA_EVENTOS") — atalho pra
; quando só o nome da última subpasta muda entre uma exportação e outra,
; evitando ter que reabrir o "Procurar..." inteiro toda vez.
SubirPasta(*) {
    global g_Gui

    pastaAtual := RTrim(Trim(g_Gui["CampoPasta"].Value), "\/")
    if (pastaAtual = "")
        return

    ; Já é a raiz de um drive (ex.: "A:") — não há como subir mais.
    if RegExMatch(pastaAtual, "^[A-Za-z]:$")
        return

    pastaPai := RegExReplace(pastaAtual, "[\\/][^\\/]*$", "")

    ; Se sobrou só a letra do drive (ex.: de "A:\Pasta" pra "A:"), completa
    ; com a barra pra virar uma raiz válida ("A:\") em vez de um caminho
    ; incompleto.
    if RegExMatch(pastaPai, "^[A-Za-z]:$")
        pastaPai := pastaPai . "\"

    if (pastaPai = "" || pastaPai = pastaAtual)
        return

    g_Gui["CampoPasta"].Value := pastaPai
}

; Abre um mini calendário (janela filha, com MonthCal nativo do Windows —
; mesma ideia visual do calendário da página) pra escolher visualmente o
; mês/ano de "nomeCampo" (CampoData1 ou CampoData2) em vez de digitar
; "AAAAMM" na mão. O campo continua aceitando digitação normal também —
; isso é só um atalho opcional, não substitui o Edit.
AbrirCalendario(nomeCampo) {
    global g_Gui

    valorAtual := Trim(g_Gui[nomeCampo].Value)

    popup := Gui("+Owner" . g_Gui.Hwnd . " +ToolWindow", "Escolher mês")
    popup.SetFont("s10")
    popup.MarginX := 10
    popup.MarginY := 10

    mc := popup.AddMonthCal("vMesCal")
    ; Se o campo já tiver um "AAAAMM" válido digitado, abre o calendário
    ; já naquele mês (dia 01) em vez de sempre cair no mês atual.
    if RegExMatch(valorAtual, "^\d{6}$")
        try mc.Value := valorAtual . "01"

    popup.AddButton("Default xm w100 y+10", "OK").OnEvent("Click", ConfirmarCalendario.Bind(popup, mc, nomeCampo))
    popup.OnEvent("Close", (*) => popup.Destroy())
    popup.Show("AutoSize")
}

; Só o mês/ano do dia escolhido é usado (Iniciar() já calcula sozinho o 1º
; e o último dia de cada mês) — o dia específico clicado no calendário não
; tem efeito nenhum no processamento.
ConfirmarCalendario(popup, mc, nomeCampo, *) {
    global g_Gui
    g_Gui[nomeCampo].Value := SubStr(mc.Value, 1, 6)
    popup.Destroy()
}

; Preenche só a caixa "Tipo Folha" na página, com base no dropdown — único
; jeito de acionar isso (não tem hotkey dedicado). Separado de AplicarConta
; pra cada botão mexer em UM campo por vez (aplicar os dois em sequência
; arriscava a busca/limpeza de um interferir no outro, já que dividem a
; mesma página).
; Núcleo compartilhado por AplicarTipoFolha (FAPS) e AplicarTipoFolhaES
; (e-Social) — os códigos (TIPO_FOLHA_*) são os MESMOS nos dois fluxos
; (confirmado contra a tabela "Tipo da folha" do manual e-Social — IPAM/
; Prefeitura/Câmara = Normal, Inativos e Pensionistas = Pensionistas ou
; Inativos, dependendo da subclasse escolhida). Cada botão só passa o
; texto do PRÓPRIO dropdown.
AplicarTipoFolhaComTexto(textoTipoFolha) {
    global TIPO_FOLHA_NORMAL, TIPO_FOLHA_PENSIONISTAS, TIPO_FOLHA_INATIVOS

    if InStr(textoTipoFolha, "Normal")
        InserirTipoFolha(TIPO_FOLHA_NORMAL)
    else if InStr(textoTipoFolha, "Pensionistas")
        InserirTipoFolha(TIPO_FOLHA_PENSIONISTAS)
    else if InStr(textoTipoFolha, "Inativos")
        InserirTipoFolha(TIPO_FOLHA_INATIVOS)
}

AplicarTipoFolha(*) {
    global g_Gui
    AplicarTipoFolhaComTexto(g_Gui["CampoTipoFolha"].Text)
    SalvarConfiguracoes()
}

AplicarTipoFolhaES(*) {
    global g_Gui
    AplicarTipoFolhaComTexto(g_Gui["CampoTipoFolhaES"].Text)
    SalvarConfiguracoes()
}

; Preenche só a caixa "Conta" na página, com base no campo "Classe de
; Conta" — único jeito de acionar isso (não tem hotkey dedicado). Ver
; comentário em AplicarTipoFolha. Aceita tanto uma das classes pré-
; definidas quanto códigos avulsos digitados na hora (ex.: "100, 200,
; 300") — ver DividirCodigos em Utilitarios.ahk.
AplicarConta(*) {
    global g_Gui, entidade, prefix, CLASSE_A, CLASSE_S, CLASSE_D, SUFIXO_A, SUFIXO_S, SUFIXO_D
    global CLASSE_RPC_PREFEITURA, CLASSE_RPC_FAS, CLASSE_RPC_CAMARA
    global SUFIXO_RPC_PREFEITURA, SUFIXO_RPC_FAS, SUFIXO_RPC_CAMARA

    ; Sincroniza a entidade escolhida na interface ANTES de montar o
    ; prefixo do arquivo (InserirContas usa a global "entidade" diretamente).
    entidade := g_Gui["CampoEntidade"].Text

    textoClasse := g_Gui["CampoClasse"].Text
    if InStr(textoClasse, "A - ")
        InserirContas(CLASSE_A, SUFIXO_A)
    else if InStr(textoClasse, "S - ")
        InserirContas(CLASSE_S, SUFIXO_S)
    else if InStr(textoClasse, "D - ")
        InserirContas(CLASSE_D, SUFIXO_D)
    else if InStr(textoClasse, "RPC") {
        ; RPC não tem uma lista fixa: o conjunto de códigos (e o prefixo do
        ; nome do arquivo, já maiúsculo/sem acento) depende da Entidade
        ; digitada — ver DetectarGrupoRPC (Utilitarios.ahk) e o comentário
        ; junto de CLASSE_RPC_* no topo do script.
        grupo := DetectarGrupoRPC(entidade)
        if (grupo = "PREFEITURA")
            InserirContas(CLASSE_RPC_PREFEITURA, SUFIXO_RPC_PREFEITURA, "PREFEITURA")
        else if (grupo = "FAS")
            InserirContas(CLASSE_RPC_FAS, SUFIXO_RPC_FAS, "FAS")
        else if (grupo = "CAMARA")
            InserirContas(CLASSE_RPC_CAMARA, SUFIXO_RPC_CAMARA, "CAMARA")
        else
            TrayTip("Classe RPC", "Preencha o campo Entidade com Prefeitura, FAS ou Câmara antes de aplicar a classe RPC — o conjunto de códigos e o nome do arquivo dependem disso. O prefixo do arquivo NÃO foi alterado (continua " . prefix . ").", 2)
    }
    else if (Trim(textoClasse) != "" && textoClasse != "(nenhuma)") {
        ; Não bateu com nenhuma classe pré-definida — trata como códigos
        ; avulsos digitados pelo usuário: pega toda sequência de dígitos no
        ; texto, não importa o separador usado (vírgula, espaço, traço...).
        listaPersonalizada := DividirCodigos(textoClasse)
        if (listaPersonalizada.Length > 0) {
            sufixoPersonalizado := JuntarLista(listaPersonalizada, "_") . "_"
            InserirContas(listaPersonalizada, sufixoPersonalizado)
        } else
            TrayTip("Classe de Conta", "Não encontrei nenhum código nesse texto — digite os números separados por vírgula ou espaço (ex.: 100, 200, 300).", 2)
    }

    SalvarConfiguracoes()
}

; Le os campos, atualiza as variaveis globais que Iniciar()/ProcessarCiclo
; realmente usam, salva em disco (o que também atualiza o histórico de
; entidades), e só então inicia o processo. Usada tanto pelo botão
; "Executar" quanto pelo hotkey F1 (ver Export-Dados-2.0.ahk) — os dois
; PRECISAM passar por aqui antes de Iniciar(), senão uma entidade/data/
; pasta digitada na interface mas nunca "aplicada" por outro botão é
; silenciosamente ignorada nesse ciclo E nunca chega a ser salva (o
; histórico de entidades só é atualizado dentro de SalvarConfiguracoes).
ExecutarProcessamento() {
    global g_Gui, data1, data2, entidade, caminhoDownload

    if IsObject(g_Gui) {
        data1           := g_Gui["CampoData1"].Value
        data2           := g_Gui["CampoData2"].Value
        entidade        := g_Gui["CampoEntidade"].Text
        caminhoDownload := g_Gui["CampoPasta"].Value

        SalvarConfiguracoes()
    }

    AtualizarStatus("Rodando...")
    Iniciar()
    AtualizarStatus("Pronto")
}

BotaoExecutar(*) {
    ExecutarProcessamento()
}

; Espelha ExecutarProcessamento (FAPS), mas pro fluxo e-Social: lê os
; campos da aba e-Social, salva a config e chama IniciarESocial (ver
; ESocial.ahk) em vez de Iniciar(). Valida a Entidade aqui (em vez de só
; dentro de IniciarESocial) pra dar um aviso específico antes de sequer
; tentar ativar a janela do navegador.
ExecutarProcessamentoES() {
    global g_Gui, data1ES, data2ES, pastaBaseES, logFileES

    if IsObject(g_Gui) {
        data1ES     := g_Gui["CampoData1ES"].Value
        data2ES     := g_Gui["CampoData2ES"].Value
        pastaBaseES := g_Gui["CampoPastaES"].Value

        SalvarConfiguracoes()
    }

    chaveEntidade := ChaveEntidadeESocial(g_Gui["CampoEntidadeES"].Text)
    if (chaveEntidade = "") {
        MsgBox("Escolha uma Entidade válida (Prefeitura/IPAM/Câmara/Inativos e Pensionistas) antes de executar.", "Aviso", 48)
        return
    }

    AtualizarStatus("Rodando (e-Social)...")
    IniciarESocial(data1ES, data2ES, chaveEntidade, pastaBaseES, logFileES)
    AtualizarStatus("Pronto")
}

BotaoExecutarES(*) {
    ExecutarProcessamentoES()
}

BotaoPausar(*) {
    AlternarPausa()
}

BotaoResetar(*) {
    SalvarConfiguracoes()
    ResetarScript()
}

; Salva a configuração atual antes de fechar, pra nenhum valor digitado na
; interface (e ainda não salvo via "Aplicar"/"Executar") se perder ao sair.
GuiFechar(*) {
    SalvarConfiguracoes()
    ExitApp()
}

; ---------- Sincronização de estado (pausa/status) ----------
; DefinirPausado é o ÚNICO lugar que deve escrever em g_Pausado — além de
; setar a variável, já sincroniza botão "Pausar/Retomar" e o texto de
; Status na mesma chamada. Usada por AlternarPausa (botão/F2) e também por
; Iniciar() (Export-Dados-2.0.ahk) ao pausar automaticamente logo após um
; Reset (F3): setar g_Pausado direto ali, sem passar por aqui, deixava a
; interface mostrando "Rodando..." / botão "Pausar" mesmo com o script já
; bloqueado esperando F2 — um bug corrigido na v1.1.
DefinirPausado(pausado) {
    global g_Pausado, g_Gui

    g_Pausado := pausado

    if IsObject(g_Gui) {
        g_Gui["BotaoPausar"].Text := g_Pausado ? "Retomar" : "Pausar"
        g_Gui["BotaoPausarES"].Text := g_Pausado ? "Retomar" : "Pausar"
        AtualizarStatus(g_Pausado ? "Pausado" : "Rodando...")
    }
}

; Chamada tanto pelo botão "Pausar/Retomar" quanto pelo hotkey F2 (via
; VerificarControles em Utilitarios.ahk) — assim os dois caminhos ficam
; sempre de acordo (texto do botão e status refletem o estado real,
; independente de qual dos dois foi usado pra pausar).
AlternarPausa() {
    global g_Pausado

    novoValor := !g_Pausado
    TrayTip("AutoHotkey", novoValor ? "Pausado. Aperte F2 (ou clique em Retomar) pra continuar." : "Retomando...", 1)
    DefinirPausado(novoValor)
}

; Atualiza o status nas DUAS abas (FAPS e e-Social) — só uma delas está
; visível por vez, mas assim o usuário vê o status certo independente de
; qual aba estiver olhando (ex.: rodando e-Social com a aba FAPS aberta).
AtualizarStatus(texto) {
    global g_Gui
    if IsObject(g_Gui) {
        g_Gui["TextoStatus"].Value := "Status: " . texto
        g_Gui["TextoStatusES"].Value := "Status: " . texto
    }
}
