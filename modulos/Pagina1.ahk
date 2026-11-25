; =====================================================================
; Pagina1.ahk
; Tudo que acontece na PÁGINA 1 (Filtros Gerais): preencher Referência e
; datas, acionar Executar, e as ações manuais de configuração das caixas
; "Conta" e "Tipo Folha" (acionadas pelos botões "Aplicar Conta"/"Aplicar
; Tipo Folha" na interface, ver Interface.ahk). Portado do V2 sem mudança
; de comportamento.
; =====================================================================

; =========================================================================
; Preenche o formulário da Página 1 (Referência + datas) e aciona Executar.
; Retorna true se chegou na Página 2 com sucesso. Se falhar, já registra o
; motivo no log, soa o beep/TrayTip de aborto, volta pra página 1 e
; retorna false — quem chama (ProcessarCiclo) só precisa checar o retorno.
; =========================================================================
PreencherEExecutarPagina1(datainicio, datafim, dataTag, logFile) {
    global delayCurto, TABS_APOS_REFERENCIA, TABS_ENTRE_CAMPOS, TABS_APOS_EXECUTAR

    ; ---------- localizar campo via "Referência" ----------
    LocalizarEFocar("Referência", TABS_APOS_REFERENCIA, true)
    Aguardar(delayCurto)
    EnviarTexto(datainicio)
    RegistrarEvento("Digitar data inicio", "OK", datainicio)
    Aguardar(delayCurto)

    Loop TABS_ENTRE_CAMPOS
        EnviarTecla("{Tab}")
    RegistrarEvento("Tab entre campos", "OK", "qtd=" . TABS_ENTRE_CAMPOS)
    Aguardar(delayCurto)

    EnviarTexto(datafim)
    RegistrarEvento("Digitar data fim", "OK", datafim)
    Aguardar(delayCurto)

    ; ---------- Localizar e acionar "Executar" ----------
    ; Reenvia o Enter se a página não mudar dentro de 800ms (ver Loop abaixo).
    LocalizarEFocar("Executar", TABS_APOS_EXECUTAR)

    ; O foco chega no botão vindo de DENTRO da barra de busca do Chrome. Um
    ; Tab pra frente e um Shift+Tab de volta refaz o "pouso" por navegação
    ; normal, sem pegada da barra de busca — o handler de clique do botão
    ; reconhece melhor esse foco.
    Aguardar(60)
    EnviarTecla("{Tab}")
    Aguardar(60)
    EnviarTecla("+{Tab}")

    Aguardar(150)

    chegouPagina2 := false
    Loop 2 {
        EnviarTecla("{Enter}")
        RegistrarEvento("Confirmar Executar (tentativa " . A_Index . ")", "OK")

        if AguardarPagina("PAGINA2", 0.8, &pagAtual, 100) {
            chegouPagina2 := true
            break
        }
        RegistrarEvento("Executar sem efeito ainda", "AVISO", "tentativa=" . A_Index . " pagina='" . pagAtual . "'")

        ; Só tenta de novo se a página estiver num estado CONHECIDO e seguro
        ; (PAGINA1 = form ainda ali; SEM_LEITURA = foco ainda no botão). Uma
        ; página DESCONHECIDA pode já ter mudado pra outra coisa — melhor
        ; parar do que mandar Enter às cegas e clicar em algo errado.
        if (pagAtual != "PAGINA1" && pagAtual != "SEM_LEITURA") {
            RegistrarEvento("Executar: parando retries", "AVISO", "pagina inesperada='" . pagAtual . "', nao vou reenviar Enter as cegas")
            break
        }
    }

    ; ---------- Se as tentativas rápidas não bastaram, dá mais uma chance
    ; com timeout maior antes de desistir de vez ----------
    ; intervaloChecagemMs=100 (aqui e acima, menor que o padrão de ~400ms do
    ; resto do script) pra perceber o quanto antes quando a tela de
    ; carregamento (DetectarPagina/CARREGANDO) vira PAGINA2.
    if !chegouPagina2 && !AguardarPagina("PAGINA2", 8, &pagAtual, 100) {
        FileAppend(dataTag . ";ABORTADO - esperava PAGINA2 apos Executar, detectado '" . pagAtual . "' | Etapa: pos-Executar (envio do formulario da pagina 1). Verifique TABS_APOS_REFERENCIA/TABS_ENTRE_CAMPOS/TABS_APOS_EXECUTAR`n", logFile)
        RegistrarEvento("Pos-Executar", "ABORTADO", "esperava PAGINA2, detectado='" . pagAtual . "'")
        TrayTip("Ciclo abortado", dataTag . ": não chegou na página de resultados (" . pagAtual . ")", 16)
        VoltarParaPrimeiraPagina(dataTag, logFile)
        return false
    }

    return true
}

; =========================================================================
; AÇÃO MANUAL (botão "Aplicar Conta" na interface) — preenche a caixa
; "Conta" com os códigos da classe escolhida. NÃO faz parte do ciclo
; automático (F1); é disparada pelo usuário antes de iniciar os ciclos,
; com o foco já na janela certa.
;
; Mecânica (diferente de LocalizarEFocar):
;   Ctrl+F -> digita "Conta" -> 3x Enter (avança até a ocorrência certa,
;   necessário desde que mais contas passaram a aparecer na página) ->
;   Shift+Tab -> Enter (fecha a busca) -> Tab (entra na caixa de texto).
; Depois, para cada código da lista: digita o valor, Tab (sai da caixa,
; confirmando o valor) e Shift+Tab (volta pra caixa) antes do próximo.
; =========================================================================
; entidadeParaArquivo (opcional) — usada só pra classe RPC (ver AplicarConta
; em Interface.ahk): a caixa "Conta" na página recebe o mesmo, mas o PREFIXO
; do nome do arquivo usa esse valor (ex.: "PREFEITURA", "FAS", "CAMARA", já
; maiúsculo e sem acento) em vez da variável global "entidade" (que pode
; estar como o usuário digitou, ex.: "Prefeitura"). Deixa "entidade"/o combo
; da interface intactos.
; faltandoSaida (saída por referência, opcional): repassa o mesmo parâmetro
; de InserirCampoMultiSelect — ver ali e ExecutarProcessamento (Interface.ahk).
InserirContas(listaContas, novoSufixo, entidadeParaArquivo := "", &faltandoSaida := "") {
    global g_UltimoTickAcao, prefix, entidade, ARQUIVO_ESTADO_PREFIX, g_Gui

    ; Reseta o marcador de tempo ANTES de qualquer Send, pra medir só o
    ; tempo que a própria função leva — a espera do usuário até apertar o
    ; botão não pode contar como "ação lenta" pro RegistrarEvento.
    g_UltimoTickAcao := A_TickCount

    ; ---------- Aviso (só diagnóstico, não bloqueia) se a página não
    ; parece ser da entidade escolhida — o nome do órgão logado aparece no
    ; cabeçalho, repetido no início do texto capturado. Evita aplicar a
    ; classe RPC de uma entidade na aba/janela de outra sem perceber. ----------
    ; (versão anterior, mantida comentada — lia o cabeçalho da página
    ; inteira via Ctrl+A/Ctrl+C; ver DetectarOrgaoPagina em Utilitarios.ahk)
    ; if (entidadeParaArquivo != "") {
    ;     orgaoDetectado := DetectarOrgaoPagina(CapturarResumoPagina(1500))
    ;     if (orgaoDetectado != "" && orgaoDetectado != entidadeParaArquivo)
    ;         TrayTip("Atenção: confira a entidade", "Aplicando classe RPC de " . entidadeParaArquivo . ", mas a página parece ser de " . orgaoDetectado . " — confira se está na janela/aba certa.", 2)
    ; }
    if (entidadeParaArquivo != "") {
        entidadeDetectada := DetectarEntidadeURL(CapturarUrlOuCaminho())
        if (entidadeDetectada != "" && entidadeDetectada != entidadeParaArquivo)
            TrayTip("Atenção: confira a entidade", "Aplicando classe RPC de " . entidadeParaArquivo . ", mas a URL parece ser de " . entidadeDetectada . " — confira se está na janela/aba certa.", 2)
    }

    ; Limpar usa "Matrícula:" (primeiro campo da seção seguinte, único na
    ; página — ver comentário em InserirCampoMultiSelect) como âncora.
    ; entersLimpar=0: não confirma "Matrícula:" com Enter, vai direto pro
    ; Shift+Tab+Enter que fecha a busca. shiftTabsExtrasAposFechar=2: como
    ; "Matrícula:" fica mais longe do botão "Limpar" na ordem de tabulação
    ; que "Referência" (Tipo Folha), precisa de 2 Shift+Tab extras depois de
    ; fechar a busca pra alcançá-lo.
    ;
    ; O prefixo (e classe_atual.txt) só são trocados MAIS ABAIXO, depois de
    ; confirmar que a página aceitou os códigos — se a página rejeitar (ex.:
    ; classe "Normal" numa consulta de Inativos), o prefixo continua o
    ; anterior em vez de assumir uma classe que a caixa "Conta" não aceitou.
    faltandoConta := ""
    if !InserirCampoMultiSelect(listaContas, "Conta", 3, true, true, "Matrícula:", 0, 2, &faltandoConta) {
        faltandoSaida := faltandoConta
        TrayTip("Atenção: confira a caixa Conta", "A página rejeitou um ou mais códigos como incompatíveis com essa consulta — confira manualmente antes de rodar os ciclos. O prefixo do nome do arquivo NÃO foi alterado (continua " . prefix . ").", 2)
        if IsObject(g_Gui)
            WinActivate("ahk_id " . g_Gui.Hwnd)
        return
    }

    ; Verificacao imediata apos inserir: se faltou codigo, tenta uma vez
    ; apenas os faltantes (sem limpar o que ja entrou) e re-verifica.
    if (faltandoConta != "") {
        faltandoRetry := ""
        codigosFaltantes := DividirCodigos(faltandoConta)
        if (codigosFaltantes.Length > 0) {
            if !InserirCampoMultiSelect(codigosFaltantes, "Conta", 3, true, true, "Matrícula:", 0, 2, &faltandoRetry, "{Enter}", false) {
                TrayTip("Atenção: confira a caixa Conta", "A página rejeitou um ou mais códigos como incompatíveis com essa consulta — confira manualmente antes de rodar os ciclos. O prefixo do nome do arquivo NÃO foi alterado (continua " . prefix . ").", 2)
            } else {
                faltandoConta := faltandoRetry
            }
        }
    }

    faltandoSaida := faltandoConta
    if (faltandoConta != "")
        TrayTip("Confira a caixa Conta", "Código(s) aparentemente não inserido(s): " . faltandoConta, 2)

    ; Troca o prefixo do nome de arquivo pra "ENTIDADE_sufixoDaClasse" —
    ; vale pra todos os ciclos exportados a partir de agora, até a próxima
    ; troca de classe. StrUpper(RemoverAcentos()) no fallback pra
    ; "entidade": esse vem direto do que o usuário digitou/escolheu na
    ; interface (ex.: "Prefeitura", "Câmara"), sem case fixo e com acento —
    ; RemoverAcentos tira o acento (ex.: "Câmara" -> "CAMARA", igual o
    ; literal "CAMARA" que a classe RPC já usa, ver AplicarConta/
    ; Interface.ahk) antes de forçar maiúsculas. entidadeParaArquivo (RPC)
    ; já vem pronto (maiúsculas, sem acento), não precisa passar por isso de novo.
    prefix := (entidadeParaArquivo != "" ? entidadeParaArquivo : StrUpper(RemoverAcentos(entidade))) . "_" . novoSufixo

    ; Grava a escolha em disco pra sobreviver a um reset (F3).
    if FileExist(ARQUIVO_ESTADO_PREFIX)
        FileDelete(ARQUIVO_ESTADO_PREFIX)
    FileAppend(prefix, ARQUIVO_ESTADO_PREFIX)

    TrayTip("Classe selecionada", "Prefixo agora: " . prefix, 1)

    ; Devolve o foco pro painel — essas ações mexem no navegador
    ; (WinActivate(janelaAlvo) em InserirCampoMultiSelect) e deixam o foco lá.
    if IsObject(g_Gui)
        WinActivate("ahk_id " . g_Gui.Hwnd)
}

; Tipo da folha (botão "Aplicar Tipo Folha" na interface) — mesmo padrão do
; Conta, mas Limpar usa "Referência" (campo seguinte a "Tipo Folha" na
; página) como âncora. Não mexe no prefixo do arquivo (só InserirContas mexe).
; faltandoSaida (saída por referência, opcional): repassa o mesmo parâmetro
; de InserirCampoMultiSelect — ver ali e ExecutarProcessamento (Interface.ahk).
InserirTipoFolha(listaCodigos, &faltandoSaida := "") {
    global g_UltimoTickAcao, g_Gui
    g_UltimoTickAcao := A_TickCount

    faltando := ""
    if !InserirCampoMultiSelect(listaCodigos, "Tipo Folha", 1, true, true, "Referência", 1, 0, &faltando) {
        faltandoSaida := faltando
        TrayTip("Atenção: confira a caixa Tipo Folha", "A página rejeitou um ou mais códigos como incompatíveis com essa consulta — confira manualmente antes de rodar os ciclos.", 2)
        if IsObject(g_Gui)
            WinActivate("ahk_id " . g_Gui.Hwnd)
        return
    }

    ; Verificacao imediata apos inserir: se faltou codigo, tenta uma vez
    ; apenas os faltantes (sem limpar o que ja entrou) e re-verifica.
    if (faltando != "") {
        faltandoRetry := ""
        codigosFaltantes := DividirCodigos(faltando)
        if (codigosFaltantes.Length > 0) {
            if !InserirCampoMultiSelect(codigosFaltantes, "Tipo Folha", 1, true, true, "Referência", 1, 0, &faltandoRetry, "{Enter}", false) {
                TrayTip("Atenção: confira a caixa Tipo Folha", "A página rejeitou um ou mais códigos como incompatíveis com essa consulta — confira manualmente antes de rodar os ciclos.", 2)
            } else {
                faltando := faltandoRetry
            }
        }
    }

    faltandoSaida := faltando
    if (faltando = "")
        TrayTip("Tipo da folha selecionado", "Códigos: " . JuntarValores(listaCodigos), 1)
    else
        TrayTip("Atenção: confira a caixa Tipo Folha", "Código(s) aparentemente não inserido(s): " . faltando, 2)

    ; Devolve o foco pro painel — mesma razão do fim de InserirContas.
    if IsObject(g_Gui)
        WinActivate("ahk_id " . g_Gui.Hwnd)
}

; ================= INSERE VALORES EM CAMPO MULTI-SELECT (busca+chips) =================
; Padrão comum aos campos "Conta" e "Tipo Folha": localizar via Ctrl+F,
; limpar valores anteriores e inserir os novos valores um de cada vez.
;
; A verificação por texto capturado na tela, é só DIAGNÓSTICO: registra no log o que viu,
; mas não repete a ação nem interrompe o usuário — rótulos repetidos na
; página e timing de AJAX geram falso alarme mesmo com a caixa certa. O
; único caso tratado como falha de verdade é a própria página REJEITAR o
; código (ver mais abaixo), que é um sinal do servidor, não uma leitura
; ambígua de texto.
;
; campoBusca      - palavra buscada no Ctrl+F (ex.: "Conta", "Tipo Folha")
; entersInserir   - Enters dados AINDA DENTRO da busca antes de fechar, pra
;                   avançar até a ocorrência certa e chegar na caixa de texto
; ativarComEnter  - se true, dá um Enter extra depois do Shift+Tab pra
;                   "ativar" o elemento onde o foco caiu.
; tabFinal        - se true, dá 1 Tab depois do Shift+Tab (e do Enter, se
;                   ativarComEnter) pra chegar na caixa de valores. Conta
;                   precisa desse Tab extra; Tipo Folha não (o Shift+Tab
;                   sozinho já cai direto na caixa) — cada campo tem seu
;                   próprio layout na página.
; campoAncoraLimpar - texto de um elemento PRÓXIMO ao botão "Limpar" desse
;                   campo, usado como âncora fixa pra chegar nele (ex.:
;                   "Referência" pro Tipo Folha, "Matrícula:" pro Conta). O
;                   botão real que limpa os valores tem tabindex="-1" (só
;                   clicável via Ctrl+F+Enter, nunca por Tab solto) e sua
;                   posição na ordem de tabulação muda conforme a
;                   quantidade de valores já selecionados. Fechar a busca é
;                   sempre o mesmo mecanismo (Shift+Tab no Chrome, 7x Tab no
;                   Firefox — ver FecharBuscaCtrlF em Utilitarios.ahk) + no
;                   máximo 1 Enter — pra "Referência" (Tipo Folha), esse
;                   Enter já cai e clica direto em Limpar. Se a caixa já
;                   estiver vazia, cai numa caixa de texto em vez do botão —
;                   o Enter aí não faz mal (o form trata Enter em campo de
;                   texto como no-op). "Matrícula:" (primeiro campo da
;                   seção seguinte ao Conta) é usado em vez do título
;                   "Filtros" porque este último não é único na página
;                   (aparece em vários títulos de seção), o que fazia o
;                   Ctrl+F acertar a ocorrência errada dependendo de onde a
;                   página estava rolada.
; shiftTabsExtrasAposFechar - quantos Shift+Tab dar DEPOIS da busca já
;                   fechada (ver acima) pra alcançar o botão "Limpar",
;                   seguidos de 1 Enter pra clicar. 0 (padrão) pra âncoras
;                   que já caem direto em Limpar ao fechar a busca (ex.:
;                   "Referência", do Tipo Folha); 2 pra "Matrícula:" (Conta).
;
; Retorna false só quando a PÁGINA reporta explicitamente um código
; incompatível ("Codigo informado nao localizado") — esse é o único sinal
; confiável o bastante pra abortar e avisar o usuário de verdade. Fora
; isso, sempre retorna true (a checagem por texto vira só log, ver acima).
; faltandoSaida (saída por referência, opcional): recebe a lista de
; códigos que pareciam faltar após a inserção (mesmo texto do "faltando"
; do log), ou "" se nenhum. Usada pelos chamadores (InserirContas/
; InserirTipoFolha) pra bloquear o início de um ciclo com códigos
; possivelmente faltando — ver ExecutarProcessamento/ExecutarProcessamentoES,
; Interface.ahk.
InserirCampoMultiSelect(listaValores, campoBusca, entersInserir, ativarComEnter, tabFinal, campoAncoraLimpar, entersLimpar := 1, shiftTabsExtrasAposFechar := 0, &faltandoSaida := "", teclaInserir := "{Enter}", limparAntes := true) {
    global janelaAlvo, delayCurto, delayMedio, g_Pausado, g_Navegador

    ; Redetecta o navegador aqui (não só em Iniciar()/IniciarESocial()): esta
    ; função também é alcançada pelos botões manuais "Aplicar Conta"/
    ; "Aplicar Tipo Folha" (Interface.ahk), que rodam antes de qualquer
    ; ciclo começar, sem passar por onde a detecção normalmente acontece.
    ; Chamada é barata (1-2 WinExist) e idempotente.
    if !DetectarNavegador() {
        MsgBox("Não encontrei uma janela do Chrome nem do Firefox rodando o sistema.`nAbra o navegador com a página certa antes de aplicar.", "Aviso", 48)
        return false
    }

    if !WinActive(janelaAlvo) {
        WinActivate(janelaAlvo)
        AguardarJanelaAtiva(janelaAlvo, 2)
    }
    
    if (limparAntes) {
        textoPre := CapturarResumoPagina(200000)
        if (textoPre != "[SEM_LEITURA]") {
            selecionadosPre := ExtrairCodigosSelecionados(TrechoDoCampoAte(textoPre, campoBusca, campoAncoraLimpar))

            unicos := Map()
            for valor in listaValores
                unicos[valor] := true

            confere := (selecionadosPre.Count = unicos.Count)
            if (confere) {
                for valor in unicos {
                    if !selecionadosPre.Has(valor) {
                        confere := false
                        break
                    }
                }
            }

            if (confere) {
                RegistrarEvento("Inserir " . campoBusca . ": ja correto, pulando limpar/inserir", "OK", "valores=" . JuntarValores(listaValores))
                faltandoSaida := ""
                return true
            }

            lidasPre := ""
            for cod, linha in selecionadosPre
                lidasPre .= (lidasPre = "" ? "" : ",") . cod
            RegistrarEvento("Inserir " . campoBusca . ": caixa difere, vai limpar e reinserir", "OK", "atuais=" . lidasPre . " pretendidos=" . JuntarValores(listaValores))
        }
    }
    
    ; ---------- Limpa a caixa ANTES de inserir (via campo-âncora seguinte) ----------
    ; "Referência" só dá 1 resultado de busca — o Ctrl+F já destaca o único
    ; match ao digitar, e 1 Enter dentro da busca confirma esse match antes
    ; do Shift+Tab que fecha ela. Já "Matrícula:" (âncora do Conta) não usa
    ; esse Enter — vai direto pro Shift+Tab+Enter que fecha a busca, por
    ; isso Conta passa entersLimpar=0 (ver InserirContas). Só no Chrome: no
    ; Firefox esse Enter de confirmação não é mandado — pula direto pro
    ; fechamento da busca depois de digitar.
    if (limparAntes) {
        EnviarTecla("^f")
        Aguardar(150)
        EnviarTecla("^a") ; seleciona TODO o texto da busca anterior — nao confia que ja venha pre-selecionado
        Aguardar(60)
        EnviarTecla("{BackSpace}") ; apaga a selecao inteira, garantindo a caixa de busca vazia antes de digitar
        Aguardar(delayCurto)
        EnviarTexto(campoAncoraLimpar)
    Aguardar(500) ; da tempo da busca assentar antes do Enter
    if (g_Navegador != "FIREFOX") {
        Loop entersLimpar {
            EnviarTecla("{Enter}")
            Aguardar(delayCurto)
        }
    }
    Aguardar(700) ; espera antes do Shift+Tab pro botao Limpar

    ; ---------- Fecha a busca (ver FecharBuscaCtrlF, Utilitarios.ahk) e
    ; chega no botão "Limpar" — mecanismo difere por navegador:
    ;   - Chrome: FecharBuscaCtrlF() fecha com Shift+Tab + 1 Enter (comEnter,
    ;     padrão). hopsAteLimpar = shiftTabsExtrasAposFechar (0 ou 2, ver
    ;     doc do parâmetro acima).
    ;   - Firefox: FecharBuscaCtrlF(false, false) fecha com 7x Tab + 1 Enter
    ;     PRÓPRIO da função (necessário em Firefox pra clicar o X e fechar a
    ;     barra — não é o Enter de comEnter, que aqui está desligado). Como
    ;     o Firefox pula o(s) Enter(s) de confirmação que o Chrome manda
    ;     antes de fechar (Loop entersLimpar, acima), soma-se entersLimpar
    ;     aos hops extras pra compensar o Tab a mais que cada Enter pulado
    ;     deixaria faltando: hopsAteLimpar = shiftTabsExtrasAposFechar + entersLimpar.
    delayBuscaLimpar := 100 ; = delayCurto (usado abaixo, fora da função, pros hops extras)
    if (g_Navegador = "FIREFOX") {
        FecharBuscaCtrlF(false, false)
        hopsAteLimpar := shiftTabsExtrasAposFechar + entersLimpar
    } else {
        FecharBuscaCtrlF()
        hopsAteLimpar := shiftTabsExtrasAposFechar
    }
    Aguardar(delayBuscaLimpar)

    if (hopsAteLimpar > 0) {
        Loop hopsAteLimpar {
            EnviarTecla("+{Tab}")
            Aguardar(delayBuscaLimpar)
        }
        EnviarTecla("{Enter}") ; clica em Limpar
        Aguardar(delayBuscaLimpar)
    }

    RegistrarEvento("Limpar caixa " . campoBusca, "OK")

    ; O clique em "Limpar" dispara um re-render AJAX (PrimeFaces) na
    ; caixa — sem esperar isso assentar, a busca seguinte mira em
    ; elementos que ainda estao pra ser substituidos e a insercao inteira
    ; erra o alvo. delayMedio em vez de delayCurto aqui pra dar tempo real
    ; da pagina assentar.
    Aguardar(delayMedio)

    ; ---------- Confere (só como DIAGNÓSTICO) se o Limpar parece ter esvaziado a caixa ----------
    ; Cada valor selecionado aparece na tabela como "número - descrição"; se
    ; esse padrão ainda aparecer no trecho isolado desse campo, tenta uma
    ; vez um Shift+Tab+Enter extra (barato, sem reabrir a busca) e registra
    ; o resultado no log. Não repete o Limpar do zero nem avisa o usuário:
    ; essa leitura é sujeita a falso alarme (rótulo repetido na página,
    ; timing de AJAX) mesmo com a caixa certa na tela.
    ;
    ; NÃO usa FecharBuscaCtrlF aqui: nesse ponto o Ctrl+F já está fechado há
    ; tempo, então isso é só um Shift+Tab de navegação normal da página
    ; (tentando alcançar o botão vizinho de novo), não um fechamento de
    ; busca — usar FecharBuscaCtrlF mandaria os 7 Tabs do mecanismo de busca
    ; do Firefox num lugar sem barra de busca aberta.
    ;
    ; Em Firefox esse retry é pulado (mantém só o log de diagnóstico): um
    ; falso alarme aqui não corrige nada e ainda ativa o que estiver focado
    ; um Tab adiante, sem garantia de que seja o botão "Limpar" certo — as
    ; suposições de ordem de tabulação do Chrome não valem pro Firefox.
    textoAposLimpar := CapturarResumoPagina(200000)
    if RegExMatch(TrechoDoCampo(textoAposLimpar, campoBusca), "\d{1,5} - ") {
        if (g_Navegador != "FIREFOX") {
            EnviarTecla("+{Tab}")
            Aguardar(delayCurto)
            EnviarTecla("{Enter}")
            Aguardar(delayMedio)
            textoAposLimpar := CapturarResumoPagina(200000)
        }
        if RegExMatch(TrechoDoCampo(textoAposLimpar, campoBusca), "\d{1,5} - ")
            RegistrarEvento("Limpar caixa " . campoBusca, "AVISO", "ainda parece ter valor(es) na caixa mesmo apos Limpar — seguindo em frente (checagem sujeita a falso alarme)")
    }
    }

    ; ---------- Localiza a caixa de novo, agora pra inserir ----------
    ; Delays mais longos aqui (iguais aos que já funcionaram pra
    ; "Referência") — rápido demais faz o Enter cair num momento errado
    ; e ativar algo indevido em vez de só fechar a busca.
    EnviarTecla("^f")
    Aguardar(150)
    EnviarTecla("^a") ; seleciona TODO o texto da busca anterior — nao confia que ja venha pre-selecionado
    Aguardar(60)
    EnviarTecla("{BackSpace}") ; apaga a selecao inteira, garantindo a caixa de busca vazia antes de digitar
    Aguardar(delayCurto)
    EnviarTexto(campoBusca)
    Aguardar(500) ; da tempo da busca assentar antes do Enter
    Loop entersInserir {
        EnviarTecla(teclaInserir)
        Aguardar(delayCurto)
    }
    Aguardar(700) ; espera antes do Shift+Tab
    FecharBuscaCtrlF(ativarComEnter)
    if (ativarComEnter)
        Aguardar(delayCurto)
    if (tabFinal) {
        EnviarTecla("{Tab}")
        Aguardar(delayCurto)
    }

    ; ---------- Insere cada valor, um de cada vez ----------
    valoresTexto := ""
       for valor in listaValores {
        EnviarTexto(valor)
        Aguardar(delayMedio)
        EnviarTecla("{Tab}")
        Aguardar(delayCurto)
        EnviarTecla("+{Tab}")
        Aguardar(delayCurto)

        valoresTexto .= (valoresTexto = "" ? "" : ",") . valor
    }

    ; ---------- Verifica (diagnóstico) se todos os valores parecem ter entrado ----------
    ; Cada valor inserido dispara um re-render AJAX (nova linha na tabela) —
    ; sem esperar assentar, a captura pode rodar antes do último valor
    ; terminar de aparecer no DOM.
    ;
    ; Shift+Tab ANTES de capturar: o loop acima termina com o foco ainda
    ; DENTRO da caixa de valor (o Tab+Shift+Tab de cada iteração só
    ; confirma o valor, não tira o foco de lá) — Ctrl+A com foco preso
    ; numa caixa de texto seleciona só o CONTEÚDO DELA, não a página
    ; inteira, então CapturarResumoPagina vinha vazio/errado e todo código
    ; aparecia como "faltando" mesmo tendo sido inserido (essa era a causa
    ; real do falso alarme "sujeita a falso alarme" — não o texto
    ; ambíguo). Um Shift+Tab tira o foco da caixa antes do Ctrl+A.
    EnviarTecla("+{Tab}")
    Aguardar(delayCurto)
    Aguardar(delayMedio)
    textoAtual := CapturarResumoPagina(200000)

    ; ÚNICO sinal tratado como falha de verdade: a própria página rejeitando
    ; o código, mostrando "Erro / Codigo informado nao localizado". Isso vem do
    ; servidor, não de uma leitura de texto ambígua.
    ;
    ; Exige as duas palavras PRÓXIMAS uma da outra (mesma frase), não só
    ; presentes em qualquer lugar dos até 200000 chars da página: duas
    ; checagens independentes de presença dariam falso positivo se
    ; "informado" e "localizado" aparecessem em pontos sem relação da tela
    ; (ex.: coluna de endereço + rótulo qualquer em outro canto).
    if RegExMatch(textoAtual, "i)informado.{0,60}localizado") {
        RegistrarEvento("Inserir " . campoBusca . ": codigo incompativel", "ERRO", "pagina reportou 'Codigo informado nao localizado' - um ou mais valores (" . valoresTexto . ") nao sao validos nesse contexto")
        return false
    }

    ; Restringe a leitura ao trecho DESSE campo (mesma lógica do "ainda há
    ; valores" acima) — sem isso, um código curto (ex.: "2", "10") pode
    ; coincidir com texto de outro campo/linha da tabela em qualquer lugar
    ; da página. Ainda assim sujeito a falso alarme, por isso vira só log
    ; (AVISO), não motivo pra travar o fluxo.
    ;
    ; Procura "valor - " (o código seguido do separador que sempre aparece
    ; antes da descrição, ex.: "1 - MENSAL", "22 - COMPLEMENTAR - AVULSAS")
    ; em vez do código sozinho — bem mais preciso que só InStr(trechoAtual,
    ; valor), que colide fácil com QUALQUER número solto na página (datas,
    ; outros códigos, etc.). A descrição em si NÃO é usada na comparação
    ; porque varia por entidade pro mesmo código (confirmado: "22" aparece
    ; como "Complementar - Folhas avulsas" numa entidade e "COMPLEMENTAR -
    ; AVULSAS" noutra) — só o "código + travessão" é estável entre todas.
    trechoAtual := TrechoDoCampoAte(textoAtual, campoBusca, campoAncoraLimpar)
    selecionados := ExtrairCodigosSelecionados(trechoAtual)

    faltando := ""
    for valor in listaValores
        if !selecionados.Has(valor)
            faltando .= (faltando = "" ? "" : ",") . valor

    linhasLidas := ""
    for cod, linha in selecionados
        linhasLidas .= (linhasLidas = "" ? "" : " ## ") . linha

    faltandoSaida := faltando

    if (faltando = "")
        RegistrarEvento("Inserir " . campoBusca, "OK", "qtd=" . listaValores.Length . " valores=" . valoresTexto . " lidas=" . linhasLidas)
    else {
        RegistrarEvento("Inserir " . campoBusca . ": valor(es) aparentemente faltando (checagem sujeita a falso alarme)", "AVISO", "faltando=" . faltando . " valores_inseridos=" . valoresTexto . " lidas=" . linhasLidas)
        ; TrayTip visível — antes essa checagem só ia pro log_acoes.csv,
        ; sem nada na tela, então passava despercebida em tempo real (só
        ; se via revendo o log depois). Com a checagem "codigo + travessão"
        ; (bem menos sujeita a falso alarme que o InStr antigo), vale a
        ; pena avisar na hora em vez de só registrar.
        TrayTip("Confira a caixa " . campoBusca, "Código(s) aparentemente não inserido(s): " . faltando, 2)
    }

    return true
}
