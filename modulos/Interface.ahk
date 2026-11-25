; =====================================================================
; Interface.ahk
; Painel de controle: permite configurar todos os dados necessários
; (datas, entidade, pasta de destino, classe de conta, tipo de folha),
; lembra os valores entre execuções (arquivo config_v3.ini, na mesma
; pasta do script) e permite Executar/Pausar-Retomar/Resetar por botão.
; Os hotkeys F1-F3/Esc continuam funcionando normalmente — a interface é um
; caminho adicional pra eles, não substitui o teclado.
; =====================================================================

ARQUIVO_CONFIG_INTERFACE := A_ScriptDir . "\config_v3.ini"
MAX_ENTIDADES_HISTORICO  := 15
MAX_CLASSES_HISTORICO    := 15

; Entidades que sempre aparecem no combo, mesmo sem histórico salvo ainda
; (entidades digitadas pelo usuário aparecem primeiro — ver CarregarHistoricoEntidades).
ENTIDADES_PADRAO := ["IPAM", "Prefeitura", "Câmara", "FAS", "Pensionistas", "Inativos"]

; Classes fixas que sempre aparecem no combo "Classe de Conta". Códigos
; avulsos digitados pelo usuário entram no histórico e aparecem ACIMA destas
; (mais recente primeiro — ver CarregarHistoricoClasses).
CLASSES_PADRAO := [
    "(nenhuma)",
    "A - 874/875/876/877/878/879",
    "S - BASE (9081/9084/9086/9089/9091/9094)",
    "D - PATRONAL (9085/9082/9087/9090/9095/9092)",
    "RPC - Previdência Complementar (conforme Entidade)"
]

g_Gui := ""

; Guardam o texto que estava no dropdown na ÚLTIMA vez que o respectivo
; botão "Aplicar" foi clicado (não persistem em disco — resetam a cada
; sessão) — comparados contra o texto ATUAL do dropdown em
; ExecutarProcessamento/ExecutarProcessamentoES pra avisar se o usuário
; trocou a seleção e esqueceu de aplicar antes de iniciar o ciclo.
; g_UltimaClasseAplicada só existe no lado FAPS — "Aplicar Conta" não tem
; equivalente no e-Social (Conta é reaplicada sozinha a cada mês, ver
; ESocial.ahk).
g_UltimoTipoFolhaAplicado   := ""
g_UltimoTipoFolhaAplicadoES := ""
g_UltimaClasseAplicada      := ""

; Guardam a lista de códigos que pareciam faltar (ver "faltandoSaida" em
; InserirCampoMultiSelect, Pagina1.ahk) na última vez que o respectivo
; "Aplicar" foi clicado — "" se nenhum. Checados em ExecutarProcessamento/
; ExecutarProcessamentoES pra travar o início do ciclo se algum código
; parece não ter entrado, em vez de só logar/TrayTip silencioso.
g_ValoresFaltandoTipoFolha   := ""
g_ValoresFaltandoTipoFolhaES := ""
g_ValoresFaltandoConta       := ""

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

; Histórico salvo (mais recente primeiro) + entidades padrão que ainda não
; estejam nele, pro combo nunca ficar vazio.
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

; Move novaEntidade pro topo do histórico (sem duplicar, case-insensitive),
; limita o tamanho e grava. Retorna a lista atualizada, ou "" se não houver
; nada pra salvar.
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

; Reconstrói os itens do combo de entidade preservando o texto digitado,
; pra uma entidade nova aparecer na lista sem precisar reabrir a interface.
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
; guarda conjuntos de códigos avulsos digitados pelo usuário (ex.: "100, 200,
; 300"), pra poder reescolher depois em vez de só lembrar o último (ver
; DividirCodigos/AplicarConta).
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

; Move novaClasse pro topo do histórico (sem duplicar, case-insensitive),
; limita o tamanho e grava. "(nenhuma)" nunca é salva — é só o placeholder de
; "sem classe aplicada", não uma classe de verdade.
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

; Reconstrói os itens do combo de classe preservando o texto digitado, pra
; um código avulso novo aparecer na lista sem precisar reabrir a interface.
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
; Também atualiza os históricos de Entidade/Classe. Todo o corpo roda dentro
; de Try/Catch porque isso também é chamado durante o fechamento da janela
; (GuiFechar), quando controles individuais podem já ter sido destruídos —
; se isso acontecer no meio da leitura, desiste silenciosamente em vez de
; mostrar erro (o que já foi salvo até ali continua gravado).
SalvarConfiguracoes() {
    global g_Gui, ARQUIVO_CONFIG_INTERFACE

    if !IsObject(g_Gui)
        return

    Try {
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
    } Catch {
        ; Silenciosamente desiste no meio — ver comentário grande acima do
        ; cabeçalho da função. O que já tinha sido salvo ANTES de bater
        ; nesse erro (linhas já executadas com sucesso) já está gravado em
        ; disco normalmente; só o resto fica pra próxima chamada bem-sucedida.
    }
}

; ---------- Monta a janela ----------
CriarInterface() {
    global g_Gui, data1, data2, entidade, caminhoDownload, ARQUIVO_CONFIG_INTERFACE, g_Pausado
    global g_PosOriginal, g_LarguraBase, g_AlturaBase
    global data1ES, data2ES, pastaBaseES

    g_Gui := Gui("+Resize", "Export-Dados-2.4")
    g_Gui.SetFont("s10")
    g_Gui.MarginX := 12
    g_Gui.MarginY := 10
    g_Gui.OnEvent("Close", GuiFechar)

    ; ---------- Abas: "FAPS" (painel original) e "e-Social" (exportação
    ; Consultas Dinâmicas → Consulta Eventos pros portais do manual — ver
    ; bloco mais abaixo e modulos/ESocial.ahk). UseTab(n) associa os
    ; controles adicionados A SEGUIR à aba n; UseTab() sem argumento (mais
    ; abaixo) encerra essa associação.
    ; w680: a linha mais larga (Pasta de destino + campo + botões
    ; "Procurar.../◀") precisa desse tanto pra não cortar o "Procurar...".
    abas := g_Gui.AddTab3("vAbaPainel w680 h480", ["FAPS", "e-Social"])
    ; Guarda a posição do controle de abas: "xp/yp" só enxergam o ÚLTIMO
    ; controle adicionado, então não dá pra usar isso pra posicionar o
    ; conteúdo da aba 2 (que vem depois de vários controles da aba 1).
    abas.GetPos(&abaX, &abaY)
    abas.UseTab(1)

    ; Campo aceita "AAAAMM" digitado direto (ex.: 202607) — o botão
    ; "Calendário..." é só um atalho que abre um mini calendário (ver
    ; AbrirCalendario mais abaixo) e preenche o campo com o mês/ano
    ; escolhido, sem travar a digitação manual.
    ; "Section" marca esta posição como referência pra "xs" nas linhas
    ; seguintes — "xm" volta pra margem da JANELA (não da aba), o que
    ; jogaria essas linhas pra fora da área visível da aba.
    g_Gui.AddText("xp+12 yp+35 w150 Section", "Data início (AAAAMM):")
    g_Gui.AddEdit("vCampoData1 w150 x+10 yp-3", data1)
    g_Gui.AddButton("x+5 yp-3 w90", "Calendário...").OnEvent("Click", (*) => AbrirCalendario("CampoData1"))

    g_Gui.AddText("w150 xs", "Data fim (AAAAMM):")
    g_Gui.AddEdit("vCampoData2 w150 x+10 yp-3", data2)
    g_Gui.AddButton("x+5 yp-3 w90", "Calendário...").OnEvent("Click", (*) => AbrirCalendario("CampoData2"))

    ; Entidade: ComboBox editável — digitar entidade nova OU escolher uma já
    ; usada antes (histórico gravado em config_v3.ini, ver CarregarHistoricoEntidades).
    g_Gui.AddText("w150 xs", "Entidade:")
    g_Gui.AddComboBox("vCampoEntidade w250 x+10 yp-3", CarregarHistoricoEntidades())
    g_Gui["CampoEntidade"].Text := entidade

    g_Gui.AddText("w150 xs", "Pasta de destino:")
    g_Gui.AddEdit("vCampoPasta w370 x+10 yp-3", caminhoDownload)
    g_Gui.AddButton("vBotaoProcurar x+5 yp-3 w70", "Procurar...").OnEvent("Click", EscolherPasta)
    ; "◀": sobe um nível na pasta atual (ver SubirPasta mais abaixo).
    g_Gui.AddButton("vBotaoSubirPasta x+5 yp-3 w30", "◀").OnEvent("Click", SubirPasta)

    g_Gui.AddText("w150 xs", "Tipo de Folha:")
    g_Gui.AddDropDownList("vCampoTipoFolha w440 x+10 yp-3", [
        "(nenhum)",
        "Normal (IPAM/Prefeitura/Câmara/FAS)",
        "Pensionistas",
        "Inativos"
    ])
    ; Classe de Conta: ComboBox editável — escolhe uma classe pré-definida/já
    ; usada OU digita códigos de conta avulsos (ex.: "100, 200, 300") pra
    ; quando nenhuma classe pronta serve. Ver AplicarConta (distingue os
    ; casos) e DividirCodigos em Utilitarios.ahk (extrai os números do texto
    ; digitado, aceitando qualquer separador).
    g_Gui.AddText("w150 xs", "Classe de Conta:")
    g_Gui.AddComboBox("vCampoClasse w440 x+10 yp-3", CarregarHistoricoClasses())
    g_Gui.AddText("vTextoAvisoClasse xs y+2 w440 cGray", "Ou digite códigos avulsos separados por vírgula/espaço (ex.: 100, 200, 300). RPC exige Entidade = Prefeitura, FAS ou Câmara")

    ; Restaura classe/tipo de folha salvos. CampoClasse usa .Text (não
    ; .Choose) porque o valor salvo pode ser um código avulso digitado, que
    ; não é item da lista.
    g_Gui["CampoClasse"].Text := IniRead(ARQUIVO_CONFIG_INTERFACE, "Config", "Classe", "(nenhuma)")

    try g_Gui["CampoTipoFolha"].Choose(IniRead(ARQUIVO_CONFIG_INTERFACE, "Config", "TipoFolha", "(nenhum)"))
    catch
        g_Gui["CampoTipoFolha"].Choose(1)

    ; Botões separados (não um único "Aplicar Conta/Tipo Folha"): aplicar os
    ; dois em sequência arrisca a busca/limpeza de um campo interferir no
    ; outro, já que ambos vivem na mesma página web.
    g_Gui.AddButton("vBotaoAplicarTipoFolha xs w250 y+15", "Aplicar Tipo Folha na página").OnEvent("Click", AplicarTipoFolha)
    g_Gui.AddButton("vBotaoAplicarConta x+10 w250", "Aplicar Conta na página").OnEvent("Click", AplicarConta)

    g_Gui.AddText("vTextoStatus xs w520 y+20 cBlue", "Status: Pronto")

    g_Gui.AddButton("vBotaoExecutar xs w170 y+10", "Executar").OnEvent("Click", BotaoExecutar)
    g_Gui.AddButton("vBotaoPausar x+10 w170", g_Pausado ? "Retomar" : "Pausar").OnEvent("Click", BotaoPausar)
    g_Gui.AddButton("vBotaoResetar x+10 w170", "Resetar").OnEvent("Click", BotaoResetar)

    g_Gui.AddText("vTextoHotkeys xs y+15 w520 cGray", "Teclas: F1 Executar/Retomar | F2 Pausar | F3 Resetar | Esc Sair")

    ; ---------- Aba "e-Social" ----------
    ; Reaproveita os mesmos mecanismos do FAPS onde possível: AbrirCalendario
    ; (parametrizado por nome de campo), AplicarTipoFolhaComTexto e os
    ; handlers de pausa/reset (não são específicos de aba). "Entidade" aqui é
    ; uma lista FIXA (DropDownList) com só os portais do manual — Inativos e
    ; Pensionistas são entidades separadas (cada uma gera seu próprio
    ; arquivo/prefixo, ver ObterContaESocial em ESocial.ahk), então texto
    ; livre não se aplica como no combo do FAPS.
    ; Sem botão "Aplicar Conta": a Conta é calculada e reaplicada sozinha a
    ; cada mês do lote (ver ProcessarCicloESocial em ESocial.ahk), porque um
    ; dos códigos muda por mês.
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
        "Inativos",
        "Pensionistas"
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
    ; pode crescer pra 2-3 linhas visuais conforme o caminho digitado. Só
    ; "xs" (sem y explícito) faz o AutoHotkey calcular a posição pela altura
    ; REAL da linha anterior, evitando colisão com a linha do botão.
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
; e desloca o botão "Procurar..." pra continuar colado na caixa de pasta.
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

    ; Força repintar a janela inteira (com os filhos): sem isso, texto que
    ; quebra em 2 linhas (ex.: "TextoHotkeys") deixa pixels fantasma da
    ; quebra anterior quando só a área nova é repintada.
    DllCall("RedrawWindow", "ptr", GuiObj.Hwnd, "ptr", 0, "ptr", 0, "uint", 0x1 | 0x4 | 0x80 | 0x100)
}

; ---------- Handlers dos botões ----------

EscolherPasta(*) {
    global g_Gui
    pasta := DirSelect(g_Gui["CampoPasta"].Value,, "Escolha a pasta de destino")
    if (pasta != "")
        g_Gui["CampoPasta"].Value := pasta
}

; Mesma ideia de EscolherPasta, pra pasta BASE do e-Social — a subpasta
; "MMAAAA\CONSULTA EVENTOS" é montada sozinha por ciclo (ver PastaCicloESocial em ESocial.ahk).
EscolherPastaES(*) {
    global g_Gui
    pasta := DirSelect(g_Gui["CampoPastaES"].Value,, "Escolha a pasta base do e-Social")
    if (pasta != "")
        g_Gui["CampoPastaES"].Value := pasta
}

; Sobe um nível a partir da pasta atual no campo (ex.:
; "...\CONSULTA_EVENTOS\FAPSPENS" -> "...\CONSULTA_EVENTOS").
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

; Abre um mini calendário (MonthCal nativo do Windows) pra escolher
; visualmente o mês/ano de "nomeCampo" (CampoData1/2 ou suas versões ES),
; sem impedir a digitação manual de "AAAAMM" no campo.
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

; Preenche só a caixa "Tipo Folha" na página, com base no texto do dropdown.
; Núcleo compartilhado por AplicarTipoFolha (FAPS) e AplicarTipoFolhaES
; (e-Social) — os códigos TIPO_FOLHA_* são os mesmos nos dois fluxos; cada
; botão só passa o texto do próprio dropdown.
AplicarTipoFolhaComTexto(textoTipoFolha, &faltandoSaida := "") {
    global TIPO_FOLHA_NORMAL, TIPO_FOLHA_PENSIONISTAS, TIPO_FOLHA_INATIVOS

    if InStr(textoTipoFolha, "Normal")
        InserirTipoFolha(TIPO_FOLHA_NORMAL, &faltandoSaida)
    else if InStr(textoTipoFolha, "Pensionistas")
        InserirTipoFolha(TIPO_FOLHA_PENSIONISTAS, &faltandoSaida)
    else if InStr(textoTipoFolha, "Inativos")
        InserirTipoFolha(TIPO_FOLHA_INATIVOS, &faltandoSaida)
}

AplicarTipoFolha(*) {
    global g_Gui, g_UltimoTipoFolhaAplicado, g_ValoresFaltandoTipoFolha
    AplicarTipoFolhaComTexto(g_Gui["CampoTipoFolha"].Text, &faltando)
    g_UltimoTipoFolhaAplicado := g_Gui["CampoTipoFolha"].Text
    g_ValoresFaltandoTipoFolha := faltando
    SalvarConfiguracoes()
}

AplicarTipoFolhaES(*) {
    global g_Gui, g_UltimoTipoFolhaAplicadoES, g_ValoresFaltandoTipoFolhaES
    AplicarTipoFolhaComTexto(g_Gui["CampoTipoFolhaES"].Text, &faltando)
    g_UltimoTipoFolhaAplicadoES := g_Gui["CampoTipoFolhaES"].Text
    g_ValoresFaltandoTipoFolhaES := faltando
    SalvarConfiguracoes()
}

; Preenche só a caixa "Conta" na página, com base no campo "Classe de
; Conta" — aceita tanto uma classe pré-definida quanto códigos avulsos
; digitados na hora (ex.: "100, 200, 300", ver DividirCodigos em Utilitarios.ahk).
AplicarConta(*) {
    global g_Gui, entidade, prefix, CLASSE_A, CLASSE_S, CLASSE_D, SUFIXO_A, SUFIXO_S, SUFIXO_D
    global CLASSE_RPC_PREFEITURA, CLASSE_RPC_FAS, CLASSE_RPC_CAMARA
    global SUFIXO_RPC_PREFEITURA, SUFIXO_RPC_FAS, SUFIXO_RPC_CAMARA
    global g_UltimaClasseAplicada, g_ValoresFaltandoConta

    ; Sincroniza a entidade escolhida ANTES de montar o prefixo do arquivo
    ; (InserirContas usa a global "entidade" diretamente).
    entidade := g_Gui["CampoEntidade"].Text

    textoClasse := g_Gui["CampoClasse"].Text
    g_UltimaClasseAplicada := textoClasse
    faltando := "" ; permanece "" se nenhum ramo abaixo chamar InserirContas
    if InStr(textoClasse, "A - ")
        InserirContas(CLASSE_A, SUFIXO_A, , &faltando)
    else if InStr(textoClasse, "S - ")
        InserirContas(CLASSE_S, SUFIXO_S, , &faltando)
    else if InStr(textoClasse, "D - ")
        InserirContas(CLASSE_D, SUFIXO_D, , &faltando)
    else if InStr(textoClasse, "RPC") {
        ; RPC não tem lista fixa: o conjunto de códigos (e o prefixo do
        ; arquivo) depende da Entidade digitada — ver DetectarGrupoRPC em
        ; Utilitarios.ahk.
        grupo := DetectarGrupoRPC(entidade)
        if (grupo = "PREFEITURA")
            InserirContas(CLASSE_RPC_PREFEITURA, SUFIXO_RPC_PREFEITURA, "PREFEITURA", &faltando)
        else if (grupo = "FAS")
            InserirContas(CLASSE_RPC_FAS, SUFIXO_RPC_FAS, "FAS", &faltando)
        else if (grupo = "CAMARA")
            InserirContas(CLASSE_RPC_CAMARA, SUFIXO_RPC_CAMARA, "CAMARA", &faltando)
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
            InserirContas(listaPersonalizada, sufixoPersonalizado, , &faltando)
        } else
            TrayTip("Classe de Conta", "Não encontrei nenhum código nesse texto — digite os números separados por vírgula ou espaço (ex.: 100, 200, 300).", 2)
    }

    g_ValoresFaltandoConta := faltando
    SalvarConfiguracoes()
}

; Lê os campos, atualiza as variáveis globais que Iniciar()/ProcessarCiclo
; usam, salva em disco (o que também atualiza o histórico de entidades) e só
; então inicia o processo. Usada pelo botão "Executar" e pelo hotkey F1 (via
; ExecutarConformeAba) — precisa passar por aqui antes de Iniciar(), senão
; um valor digitado na interface mas nunca "aplicado" por outro botão é
; ignorado no ciclo e nunca chega a ser salvo.
ExecutarProcessamento() {
    global g_Gui, data1, data2, entidade, caminhoDownload, g_Pausado
    global g_UltimoTipoFolhaAplicado, g_UltimaClasseAplicada
    global g_ValoresFaltandoTipoFolha, g_ValoresFaltandoConta

    ; F1/"Executar" também funciona como "retomar" quando já está pausado
    ; (ex.: logo após um Reset/F3, que sempre reinicia pausado). Reusa
    ; AlternarPausa() em vez de duplicar a lógica de debounce/sincronismo.
    if (g_Pausado) {
        AlternarPausa()
        return
    }

    if IsObject(g_Gui) {
        data1           := g_Gui["CampoData1"].Value
        data2           := g_Gui["CampoData2"].Value
        entidade        := g_Gui["CampoEntidade"].Text
        caminhoDownload := g_Gui["CampoPasta"].Value

        ; Aviso (não bloqueia) se a Entidade é FAS e o ciclo inclui
        ; 04/2026 (202604) ou mais recente — FAS foi descontinuada, sem
        ; exportações a partir desse mês. data1 é sempre o mês MAIS
        ; RECENTE do intervalo (ver Iniciar(), Export-Dados-2.4.ahk) —
        ; se ele já bate ou passa de 202604, pelo menos parte do
        ; intervalo cai no período descontinuado.
        if (ClassificarEntidade(entidade) = "FAS" && Integer(data1) >= 202604) {
            if (MsgBox("FAS foi descontinuada — não terá mais exportações a partir de 04/2026 (202604).`n`nContinuar mesmo assim?", "Aviso", "YesNo Icon!") = "No")
                return
        }

        ; Aviso (não bloqueia) se o Tipo Folha e/ou a Classe de Conta
        ; selecionados no dropdown nunca foram de fato aplicados (botão
        ; "Aplicar..." nunca clicado pra essa seleção, ou trocada depois)
        ; — a caixa na página continuaria com o valor antigo/nenhum.
        pendencias := ""
        if (g_Gui["CampoTipoFolha"].Text != g_UltimoTipoFolhaAplicado)
            pendencias .= "- Tipo Folha (" . g_Gui["CampoTipoFolha"].Text . ")`n"
        textoClasseAtual := g_Gui["CampoClasse"].Text
        if (Trim(textoClasseAtual) != "" && textoClasseAtual != "(nenhuma)" && textoClasseAtual != g_UltimaClasseAplicada)
            pendencias .= "- Classe de Conta (" . textoClasseAtual . ")`n"
        if (pendencias != "") {
            if (MsgBox("Opção selecionada não aplicada!`n`n" . pendencias . "`nContinuar mesmo assim?", "Aviso", "YesNo Icon!") = "No")
                return
        }

        ; Aviso (não bloqueia) se a última aplicação de Tipo Folha e/ou
        ; Conta apontou código(s) aparentemente faltando na página (ver
        ; "faltandoSaida" em InserirCampoMultiSelect, Pagina1.ahk) — antes
        ; isso só ia pro log_acoes.csv/TrayTip, sem travar nada.
        faltandoCampos := ""
        if (g_ValoresFaltandoTipoFolha != "")
            faltandoCampos .= "- Tipo Folha: " . g_ValoresFaltandoTipoFolha . "`n"
        if (g_ValoresFaltandoConta != "")
            faltandoCampos .= "- Conta: " . g_ValoresFaltandoConta . "`n"
        if (faltandoCampos != "") {
            if (MsgBox("Código(s) aparentemente não inserido(s)!`n`n" . faltandoCampos . "`nContinuar mesmo assim?", "Aviso", "YesNo Icon!") = "No")
                return
        }

        ; Aviso (não bloqueia) se Entidade e Tipo Folha parecem
        ; inconsistentes (ex.: Entidade=Pensionistas com Tipo
        ; Folha=Inativos) — gera exportação diferente do normal por
        ; engano. Se o usuário confirmar mesmo assim, segue sem incomodar
        ; de novo (provavelmente sabe o que está fazendo).
        if (ClassificarGrupoFolha(entidade) != ClassificarGrupoFolha(g_Gui["CampoTipoFolha"].Text)) {
            if (MsgBox("Entidade (" . entidade . ") e Tipo Folha (" . g_Gui["CampoTipoFolha"].Text . ") parecem inconsistentes.`n`nContinuar mesmo assim?", "Aviso", "YesNo Icon!") = "No")
                return
        }

        ; Aviso (não bloqueia) se a PASTA DE DESTINO parece ser de outra
        ; entidade — convenção do usuário de nomear a última pasta com o
        ; nome da entidade (ex.: "...\CONSULTA_EVENTOS\PREFEITURA"). Só
        ; avisa quando os DOIS lados são reconhecíveis e diferentes — uma
        ; pasta com nome genérico (sem nenhuma entidade reconhecida) não
        ; gera aviso nenhum, pra não incomodar quem não segue essa convenção.
        grupoEntidadeAtual := ClassificarEntidade(entidade)
        grupoPasta := ClassificarEntidade(caminhoDownload)
        if (grupoEntidadeAtual != "" && grupoPasta != "" && grupoEntidadeAtual != grupoPasta) {
            if (MsgBox("A pasta de destino parece ser de outra entidade!`n`nEntidade selecionada: " . entidade . "`nPasta: " . caminhoDownload . "`n`nContinuar mesmo assim?", "Aviso", "YesNo Icon!") = "No")
                return
        }

        SalvarConfiguracoes()
    }

    AtualizarStatus("Rodando...")
    Iniciar()
    AtualizarStatus("Pronto")
}

BotaoExecutar(*) {
    ExecutarProcessamento()
}

; Espelha ExecutarProcessamento (FAPS) pro fluxo e-Social: lê os campos da
; aba e-Social, salva a config e chama IniciarESocial (ESocial.ahk) em vez
; de Iniciar(). Valida a Entidade aqui pra avisar antes de tentar ativar a
; janela do navegador.
ExecutarProcessamentoES() {
    global g_Gui, data1ES, data2ES, pastaBaseES, logFileES, g_Pausado
    global g_UltimoTipoFolhaAplicadoES, g_ValoresFaltandoTipoFolhaES

    ; g_Pausado é compartilhado entre FAPS e e-Social — "retomar" funciona
    ; igual em ExecutarProcessamento acima.
    if (g_Pausado) {
        AlternarPausa()
        return
    }

    if IsObject(g_Gui) {
        data1ES     := g_Gui["CampoData1ES"].Value
        data2ES     := g_Gui["CampoData2ES"].Value
        pastaBaseES := g_Gui["CampoPastaES"].Value

        SalvarConfiguracoes()
    }

    chaveEntidade := ChaveEntidadeESocial(g_Gui["CampoEntidadeES"].Text)
    if (chaveEntidade = "") {
        MsgBox("Escolha uma Entidade válida (Prefeitura/IPAM/Câmara/Inativos/Pensionistas) antes de executar.", "Aviso", 48)
        return
    }

    ; Mesmo aviso (não bloqueia) do lado FAPS — ver ExecutarProcessamento.
    if (g_Gui["CampoTipoFolhaES"].Text != g_UltimoTipoFolhaAplicadoES) {
        if (MsgBox("Opção selecionada não aplicada!`n`n- Tipo Folha (" . g_Gui["CampoTipoFolhaES"].Text . ")`n`nContinuar mesmo assim?", "Aviso", "YesNo Icon!") = "No")
            return
    }

    ; Mesmo aviso (não bloqueia) do lado FAPS — ver ExecutarProcessamento.
    if (g_ValoresFaltandoTipoFolhaES != "") {
        if (MsgBox("Código(s) aparentemente não inserido(s)!`n`n- Tipo Folha: " . g_ValoresFaltandoTipoFolhaES . "`n`nContinuar mesmo assim?", "Aviso", "YesNo Icon!") = "No")
            return
    }

    ; Mesmo aviso (não bloqueia) do lado FAPS — ver ExecutarProcessamento.
    if (ClassificarGrupoFolha(chaveEntidade) != ClassificarGrupoFolha(g_Gui["CampoTipoFolhaES"].Text)) {
        if (MsgBox("Entidade (" . g_Gui["CampoEntidadeES"].Text . ") e Tipo Folha (" . g_Gui["CampoTipoFolhaES"].Text . ") parecem inconsistentes.`n`nContinuar mesmo assim?", "Aviso", "YesNo Icon!") = "No")
            return
    }

    AtualizarStatus("Rodando (e-Social)...")
    IniciarESocial(data1ES, data2ES, chaveEntidade, pastaBaseES, logFileES)
    AtualizarStatus("Pronto")
}

BotaoExecutarES(*) {
    ExecutarProcessamentoES()
}

; Despacha o hotkey F1 pra ExecutarProcessamento (FAPS) ou
; ExecutarProcessamentoES (e-Social) conforme a ABA ATIVA no painel — os
; botões "Executar" já não precisam disso (cada um só existe na própria
; aba), mas o F1 não sabe de aba por si só. g_Gui["AbaPainel"].Value
; retorna o índice 1-based da aba selecionada (1=FAPS, 2=e-Social).
ExecutarConformeAba(*) {
    global g_Gui
    if (IsObject(g_Gui) && g_Gui["AbaPainel"].Value = 2)
        ExecutarProcessamentoES()
    else
        ExecutarProcessamento()
}

BotaoPausar(*) {
    AlternarPausa()
}

BotaoResetar(*) {
    ResetarScript() ; já salva a config sozinho agora (ver comentário lá) — não precisa mais chamar SalvarConfiguracoes aqui também
}

; Salva a configuração atual antes de fechar, pra nenhum valor digitado na
; interface (e ainda não salvo via "Aplicar"/"Executar") se perder ao sair.
GuiFechar(*) {
    SalvarConfiguracoes()
    ExitApp()
}

; ---------- Sincronização de estado (pausa/status) ----------
; ÚNICO lugar que deve escrever em g_Pausado: além de setar a variável, já
; sincroniza o botão "Pausar/Retomar" e o texto de Status na mesma chamada
; (setar g_Pausado direto em outro lugar deixaria a interface dessincronizada
; do estado real). Usada por AlternarPausa, Pausar (logo abaixo) e por
; Iniciar() (Export-Dados-2.2.ahk) ao pausar automaticamente após um Reset.
DefinirPausado(pausado) {
    global g_Pausado, g_Gui

    g_Pausado := pausado

    if IsObject(g_Gui) {
        g_Gui["BotaoPausar"].Text := g_Pausado ? "Retomar" : "Pausar"
        g_Gui["BotaoPausarES"].Text := g_Pausado ? "Retomar" : "Pausar"
        AtualizarStatus(g_Pausado ? "Pausado" : "Rodando...")
    }
}

; Alterna pausado<->rodando. Chamada pelo botão "Pausar/Retomar" e por
; ExecutarProcessamento/ExecutarProcessamentoES quando F1/"Executar" é usado
; pra retomar um lote já pausado — em ambos os casos o chamador já decidiu a
; direção certa antes de chamar. NÃO é chamada pelo F2 (ver Pausar() abaixo):
; esquema de hotkeys é F1 = iniciar/retomar, F2 = só pausar, F3 = reset.
; Debounce evita duplo-clique/disparo duplo acidental.
AlternarPausa() {
    global g_Pausado, g_UltimoToggleTick

    if (A_TickCount - g_UltimoToggleTick < 400)
        return
    g_UltimoToggleTick := A_TickCount

    novoValor := !g_Pausado
    TrayTip("AutoHotkey", novoValor ? "Pausado. Aperte F1 (ou clique em Retomar) pra continuar." : "Retomando...", 1)
    DefinirPausado(novoValor)
}

; F2 (hotkey nativo e o polling de VerificarControles(), Utilitarios.ahk)
; SÓ PAUSA, nunca retoma, mesmo se já estiver pausado (idempotente: só
; retorna sem fazer nada). Retomar é sempre F1 ou o botão "Retomar"
; (AlternarPausa acima). Por ser idempotente não precisa do debounce de
; AlternarPausa(): F2 detectado 2x pro mesmo toque (hotkey + polling) não
; causa problema, a 2ª chamada só vê g_Pausado já true e retorna na hora.
Pausar(*) {
    global g_Pausado

    if (g_Pausado)
        return

    TrayTip("AutoHotkey", "Pausado. Aperte F1 (ou clique em Retomar) pra continuar.", 1)
    DefinirPausado(true)
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
