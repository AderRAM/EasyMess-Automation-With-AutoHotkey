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
    Send(datainicio)
    RegistrarEvento("Digitar data inicio", "OK", datainicio)
    Aguardar(delayCurto)

    Loop TABS_ENTRE_CAMPOS
        Send("{Tab}")
    RegistrarEvento("Tab entre campos", "OK", "qtd=" . TABS_ENTRE_CAMPOS)
    Aguardar(delayCurto)

    Send(datafim)
    RegistrarEvento("Digitar data fim", "OK", datafim)
    Aguardar(delayCurto)

    ; ---------- Localizar e acionar "Executar" ----------
    ; O Enter unico com pausa de 700ms foi testado e NAO funcionou.
    ; Voltando pro retry comprovado: reenvia o Enter se a pagina nao
    ; mudar dentro de 800ms.
    LocalizarEFocar("Executar", TABS_APOS_EXECUTAR)

    ; O foco chega no botao vindo de DENTRO da barra de busca do Chrome
    ; (via Shift+Tab). Um Tab pra frente e um Shift+Tab de volta refaz
    ; esse "pouso" inteiramente por navegacao normal de Tab, sem
    ; nenhuma pegada da barra de busca — o foco fica "mais legitimo"
    ; pro handler de clique do botao reconhecer.
    Aguardar(60)
    Send("{Tab}")
    Aguardar(60)
    Send("+{Tab}")

    Aguardar(150)

    chegouPagina2 := false
    Loop 2 {
        Send("{Enter}")
        RegistrarEvento("Confirmar Executar (tentativa " . A_Index . ")", "OK")

        if AguardarPagina("PAGINA2", 0.8, &pagAtual, 100) {
            chegouPagina2 := true
            break
        }
        RegistrarEvento("Executar sem efeito ainda", "AVISO", "tentativa=" . A_Index . " pagina='" . pagAtual . "'")

        ; Só tenta de novo se ainda esta num estado CONHECIDO e seguro
        ; (PAGINA1 = form ainda ali; SEM_LEITURA = foco provavelmente
        ; ainda no botao, Ctrl+A nao seleciona nada). Se a pagina mostrar
        ; algo DESCONHECIDO, a tela pode ja ter mudado pra outra coisa —
        ; melhor parar de mandar Enter as cegas do que arriscar clicar
        ; em algo errado numa tela que nao reconhecemos.
        if (pagAtual != "PAGINA1" && pagAtual != "SEM_LEITURA") {
            RegistrarEvento("Executar: parando retries", "AVISO", "pagina inesperada='" . pagAtual . "', nao vou reenviar Enter as cegas")
            break
        }
    }

    ; ---------- VERIFICAÇÃO: se as tentativas rapidas nao bastaram, da
    ; mais uma chance com um timeout maior antes de desistir de vez ----------
    ; intervaloChecagemMs=100 nas duas chamadas (aqui e acima): depois de
    ; clicar "Executar", queremos perceber o quanto antes quando a tela de
    ; carregamento (ver DetectarPagina/CARREGANDO) termina e vira PAGINA2 —
    ; pedido explícito do usuário, em vez do padrão de ~400ms usado no
    ; resto do script (ex.: esperando PAGINA1 no início do ciclo).
    if !chegouPagina2 && !AguardarPagina("PAGINA2", 8, &pagAtual, 100) {
        FileAppend(dataTag . ";ABORTADO - esperava PAGINA2 apos Executar, detectado '" . pagAtual . "' | Etapa: pos-Executar (envio do formulario da pagina 1). Verifique TABS_APOS_REFERENCIA/TABS_ENTRE_CAMPOS/TABS_APOS_EXECUTAR`n", logFile)
        RegistrarEvento("Pos-Executar", "ABORTADO", "esperava PAGINA2, detectado='" . pagAtual . "'")
        SoundBeep(500, 300)
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
; Mecânica (diferente de LocalizarEFocar — aqui NÃO se confirma a busca
; com Enter antes de fechar):
;   Ctrl+F -> digita "Conta" -> (sem Enter) -> Shift+Tab -> Enter (fecha a
;   busca) -> Tab (entra na caixa de texto).
; Depois, para cada código da lista: digita o valor, Tab (sai da caixa,
; confirmando o valor) e Shift+Tab (volta pra caixa) antes do próximo.
; =========================================================================
; entidadeParaArquivo (opcional) — usada só pra classe RPC (ver AplicarConta,
; em Interface.ahk): a caixa "Conta" na página recebe o mesmo, mas o PREFIXO
; do nome do arquivo usa esse valor (ex.: "PREFEITURA", "FAS", "CAMARA" — já
; maiúsculo e sem acento, conforme o padrão de nome exigido) em vez da
; variável global "entidade" (que pode estar como o usuário digitou, ex.:
; "Prefeitura" ou "Câmara"). Deixa "entidade"/o combo da interface intactos.
InserirContas(listaContas, novoSufixo, entidadeParaArquivo := "") {
    global g_UltimoTickAcao, prefix, entidade, ARQUIVO_ESTADO_PREFIX

    ; InserirContas é disparada manualmente, a qualquer momento — o tempo
    ; ocioso ATÉ o usuário apertar a tecla nao pode contar como duracao da
    ; acao (senao "Registrar Evento" acusa falso alarme de "acao lenta").
    ; Reseta o marcador de tempo aqui, ANTES de qualquer Send, pra medir só
    ; o tempo que a propria funcao leva.
    g_UltimoTickAcao := A_TickCount

    ; Limpar usa "Matrícula:" (primeiro campo da seção seguinte, único na
    ; página — ver comentário em InserirCampoMultiSelect sobre por que
    ; "Filtros" foi abandonado como âncora) como âncora fixa. entersLimpar=0:
    ; depois de digitar "Matrícula:" NÃO se aperta Enter pra selecionar —
    ; vai direto pro Shift+Tab+Enter que fecha a busca (sempre só esses
    ; dois, nunca mais — ver InserirCampoMultiSelect). Como "Matrícula:"
    ; fica mais longe do botão "Limpar" na ordem de tabulação do que
    ; "Referência" (Tipo Folha), fechar a busca sozinho não é suficiente:
    ; precisa de mais 2 Shift+Tab DEPOIS de fechada, seguidos de Enter, pra
    ; alcançar e clicar em Limpar (shiftTabsExtrasAposFechar=2, confirmado
    ; pelo usuário testando ao vivo).
    ;
    ; O prefixo (e o arquivo classe_atual.txt) só são trocados MAIS ABAIXO,
    ; depois de confirmar que a página aceitou os códigos — bug corrigido
    ; na v1.1: antes, prefix/classe_atual.txt eram sobrescritos ANTES desta
    ; chamada, incondicionalmente. Se a página rejeitasse os códigos (ex.:
    ; classe "Normal" numa consulta de Inativos), o aviso "confira a caixa
    ; Conta" aparecia mas o prefixo já tinha mudado mesmo assim — se o
    ; usuário não reparasse no aviso (um TrayTip, fácil de perder) e
    ; rodasse os ciclos, os arquivos exportados saiam nomeados com uma
    ; classe que a própria página tinha rejeitado, com a caixa "Conta" na
    ; tela em estado incerto (limpa e não preenchida com sucesso).
    if !InserirCampoMultiSelect(listaContas, "Conta", 0, true, true, "Matrícula:", 0, 2) {
        TrayTip("Atenção: confira a caixa Conta", "A página rejeitou um ou mais códigos como incompatíveis com essa consulta — confira manualmente antes de rodar os ciclos. O prefixo do nome do arquivo NÃO foi alterado (continua " . prefix . ").", 2)
        return
    }

    ; Troca o prefixo do nome de arquivo pra "entidade_sufixoDaClasse" —
    ; vale pra todos os ciclos exportados a partir de agora, até a proxima
    ; troca de classe. "entidade" (IPAM, CAMARA, etc.) é definida manualmente
    ; lá no topo do script e não muda aqui.
    prefix := (entidadeParaArquivo != "" ? entidadeParaArquivo : entidade) . "_" . novoSufixo

    ; Grava a escolha em disco pra sobreviver a um reset (F3) — sem isso,
    ; resetar o script depois de escolher a classe silenciosamente esquecia
    ; a escolha e voltava pro prefixo padrão.
    if FileExist(ARQUIVO_ESTADO_PREFIX)
        FileDelete(ARQUIVO_ESTADO_PREFIX)
    FileAppend(prefix, ARQUIVO_ESTADO_PREFIX)

    TrayTip("Classe selecionada", "Prefixo agora: " . prefix, 1)
}

; --- Tipo da folha (botão "Aplicar Tipo Folha" na interface) — mesmo
; padrão do Conta, mas Limpar usa "Referência" (campo seguinte a "Tipo
; Folha" na página) como âncora — ver comentário em
; InserirCampoMultiSelect. Não mexe no prefixo do arquivo (isso é
; controlado só por InserirContas/Conta).
InserirTipoFolha(listaCodigos) {
    global g_UltimoTickAcao
    g_UltimoTickAcao := A_TickCount

    if InserirCampoMultiSelect(listaCodigos, "Tipo Folha", 1, true, true, "Referência")
        TrayTip("Tipo da folha selecionado", "Códigos: " . JuntarValores(listaCodigos), 1)
    else
        TrayTip("Atenção: confira a caixa Tipo Folha", "A página rejeitou um ou mais códigos como incompatíveis com essa consulta — confira manualmente antes de rodar os ciclos.", 2)
}

; ================= INSERE VALORES EM CAMPO MULTI-SELECT (busca+chips) =================
; Padrão comum aos campos "Conta" e "Tipo Folha": localizar via Ctrl+F,
; limpar valores anteriores (o campo ACUMULA em vez de substituir — sem
; limpar antes, trocar de classe misturaria códigos de grupos diferentes) e
; inserir os novos valores um de cada vez.
;
; A verificação por texto capturado (comparar o que apareceu na tela com o
; que devia ter sido inserido) já foi tentada com retry automático (refazer
; Limpar+inserir do zero até 2x quando "parecia" faltar algo), mas se
; mostrou pouco confiável na prática: rótulos repetidos na página (ex.:
; "Tipo Folha" aparece mais de uma vez — por isso "Tipo Folha" precisa de
; Enters extras na busca, ver entersInserir) e timing de AJAX geram falso
; alarme mesmo com a caixa 100% certa na tela — confirmado visualmente mais
; de uma vez. Um retry automático em cima de um falso alarme só reapaga
; valores que já estavam certos. Por isso agora essa checagem é só
; DIAGNÓSTICO: registra no log (log_acoes.csv) o que viu, mas não repete a
; ação nem interrompe o usuário com um aviso — o único caso tratado como
; falha de verdade é a própria página REJEITAR o código (ver mais abaixo),
; que é um sinal do servidor, não uma leitura ambígua de texto.
;
; campoBusca      - palavra buscada no Ctrl+F (ex.: "Conta", "Tipo Folha")
; entersInserir   - Enters dados AINDA DENTRO da busca antes de fechar, pra
;                   avançar até a ocorrência certa e chegar na caixa de texto
; ativarComEnter  - se true, dá um Enter extra depois do Shift+Tab pra
;                   "ativar" o elemento onde o foco caiu.
; tabFinal        - se true, dá 1 Tab depois do Shift+Tab (e do Enter, se
;                   ativarComEnter) pra chegar na caixa de valores. Conta
;                   precisa desse Tab extra; Tipo Folha NÃO (o Shift+Tab
;                   sozinho já cai direto na caixa) — cada campo tem seu
;                   próprio layout, confirmado pelo usuário.
; campoAncoraLimpar - texto de um elemento PRÓXIMO ao botão "Limpar" desse
;                   campo, usado como âncora fixa pra chegar nele (ex.:
;                   "Referência" pro Tipo Folha, "Matrícula:" pro Conta).
;                   O botão real que limpa os valores tem tabindex="-1" (só
;                   é clicável via Ctrl+F+Enter, nunca por Tab solto) e sua
;                   posição na ordem de tabulação muda conforme a
;                   quantidade de valores já selecionados. Fechar a busca é
;                   SEMPRE exatamente 1 Shift+Tab + 1 Enter (nunca mais que
;                   isso, mecanismo fixo do Chrome) — pra "Referência"
;                   (Tipo Folha), esse Enter já cai e clica direto em
;                   Limpar (confirmado pelo usuário: Referência -> Shift+Tab
;                   já seleciona o Limpar do Tipo Folha quando a caixa tem
;                   valores). Se a caixa já estiver vazia, cai numa caixa de
;                   texto em vez do botão — o Enter aí não faz mal (o form
;                   trata Enter em campo de texto como no-op, via
;                   onkeypress do form).
;                   "Filtros" (título da seção seguinte ao Conta) foi
;                   tentado antes como âncora do Conta mas foi ABANDONADO:
;                   não é único na página (aparece em pelo menos 4 títulos
;                   de seção — "Filtros Gerais", "Filtros", "Filtros
;                   Ativos/Desligados", "Salvar Filtros"), então o Ctrl+F
;                   podia acertar qualquer um deles dependendo de onde a
;                   página estava rolada, e isso só ficava evidente depois
;                   de várias trocas de Conta seguidas na mesma sessão
;                   (confirmado ao vivo pelo usuário). "Matrícula:" (o
;                   primeiro campo da seção seguinte) é único na página —
;                   sem essa ambiguidade, mas mais longe do Limpar na ordem
;                   de tabulação, por isso precisa de shiftTabsExtrasAposFechar.
; shiftTabsExtrasAposFechar - quantos Shift+Tab dar DEPOIS da busca já
;                   fechada (ver acima) pra alcançar o botão "Limpar",
;                   seguidos de 1 Enter pra clicar. 0 (padrão) pra âncoras
;                   que já caem direto em Limpar ao fechar a busca (ex.:
;                   "Referência", do Tipo Folha); 2 pra "Matrícula:" (Conta
;                   — confirmado pelo usuário testando ao vivo).
;
; Retorna false só quando a PÁGINA reporta explicitamente um código
; incompatível ("Codigo informado nao localizado") — esse é o único sinal
; confiável o bastante pra abortar e avisar o usuário de verdade. Fora
; isso, sempre retorna true (a checagem por texto vira só log, ver acima).
InserirCampoMultiSelect(listaValores, campoBusca, entersInserir, ativarComEnter, tabFinal, campoAncoraLimpar, entersLimpar := 1, shiftTabsExtrasAposFechar := 0) {
    global janelaAlvo, delayCurto, delayMedio, g_Pausado

    if !WinActive(janelaAlvo) {
        WinActivate(janelaAlvo)
        AguardarJanelaAtiva(janelaAlvo, 2)
    }

    ; ---------- Limpa a caixa ANTES de inserir (via campo-âncora seguinte) ----------
    ; "Referência" só dá 1 resultado de busca — o Ctrl+F já destaca o único
    ; match ao digitar, e 1 Enter dentro da busca confirma esse match antes
    ; do Shift+Tab que fecha ela. Já "Matrícula:" (âncora do Conta) NÃO usa
    ; esse Enter — vai direto pro Shift+Tab+Enter que fecha a busca
    ; (confirmado pelo usuário) — por isso Conta passa entersLimpar=0 (ver
    ; InserirContas).
    Send("^f")
    Aguardar(150)
    Send("^a") ; seleciona TODO o texto da busca anterior — nao confia que ja venha pre-selecionado
    Aguardar(60)
    Send("{BackSpace}") ; apaga a selecao inteira, garantindo a caixa de busca vazia antes de digitar
    Aguardar(delayCurto)
    SendText(campoAncoraLimpar)
    Aguardar(500) ; da tempo da busca assentar antes do Enter
    Loop entersLimpar {
        Send("{Enter}")
        Aguardar(delayCurto)
    }
    Aguardar(700) ; espera antes do Shift+Tab pro botao Limpar

    ; ---------- Fecha a busca: SEMPRE exatamente 1 Shift+Tab + 1 Enter,
    ; nunca mais que isso (confirmado pelo usuário) ----------
    delayBuscaLimpar := 100
    Send("+{Tab}")
    Aguardar(delayBuscaLimpar)
    Send("{Enter}") ; fecha a busca — pra "Referência" (Tipo Folha), esse
                     ; Enter já pousa e clica direto em Limpar (0 hops extras)
    Aguardar(delayBuscaLimpar)

    ; ---------- Se o fechamento não pousou direto no botão "Limpar" (ex.:
    ; "Matrícula:" do Conta, mais longe na ordem de tabulação do que
    ; "Referência" do Tipo Folha), navega os hops extras necessários — SÓ
    ; DEPOIS da busca já fechada, nunca misturado com o Shift+Tab que fecha
    ; ela — e clica. "Filtros" foi abandonado como âncora do Conta: não é
    ; único na página (aparece em pelo menos 4 títulos de seção — "Filtros
    ; Gerais", "Filtros", "Filtros Ativos/Desligados", "Salvar Filtros"),
    ; então o Ctrl+F podia acertar qualquer um deles dependendo de onde a
    ; página estava rolada (confirmado ao vivo pelo usuário; uma tentativa
    ; de verificar+repetir a ocorrência certa também não se mostrou
    ; confiável). A âncora agora é "Matrícula:" (única na página) — dali,
    ; mais 2 Shift+Tab (shiftTabsExtrasAposFechar=2, ver InserirContas)
    ; chegam no botão "Limpar" do Conta.
    if (shiftTabsExtrasAposFechar > 0) {
        Loop shiftTabsExtrasAposFechar {
            Send("+{Tab}")
            Aguardar(delayBuscaLimpar)
        }
        Send("{Enter}") ; clica em Limpar
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
    ; esse padrão ainda aparecer no trecho isolado desse campo, TENTA UMA
    ; VEZ um Shift+Tab+Enter extra (barato, sem reabrir a busca — talvez o
    ; clique anterior não tenha caído no botão certo) e registra o
    ; resultado no log. Não repete o Limpar do zero nem avisa o usuário:
    ; essa leitura já se mostrou capaz de dar falso alarme (rótulo repetido
    ; na página, timing de AJAX, texto capturado truncado) mesmo com a
    ; caixa certa na tela.
    textoAposLimpar := CapturarResumoPagina(200000)
    if RegExMatch(TrechoDoCampo(textoAposLimpar, campoBusca), "\d{1,5} - ") {
        Send("+{Tab}")
        Aguardar(delayCurto)
        Send("{Enter}")
        Aguardar(delayMedio)
        textoAposLimpar := CapturarResumoPagina(200000)
        if RegExMatch(TrechoDoCampo(textoAposLimpar, campoBusca), "\d{1,5} - ")
            RegistrarEvento("Limpar caixa " . campoBusca, "AVISO", "ainda parece ter valor(es) na caixa mesmo apos Limpar — seguindo em frente (checagem sujeita a falso alarme)")
    }

    ; ---------- Localiza a caixa de novo, agora pra inserir ----------
    ; Delays mais longos aqui (iguais aos que já funcionaram pra
    ; "Referência") — rápido demais faz o Enter cair num momento errado
    ; e ativar coisa indevida (ex.: abrir "Editar Tabela" numa janela
    ; nova) em vez de só fechar a busca.
    Send("^f")
    Aguardar(150)
    Send("^a") ; seleciona TODO o texto da busca anterior — nao confia que ja venha pre-selecionado
    Aguardar(60)
    Send("{BackSpace}") ; apaga a selecao inteira, garantindo a caixa de busca vazia antes de digitar
    Aguardar(delayCurto)
    SendText(campoBusca)
    Aguardar(500) ; da tempo da busca assentar antes do Enter
    Loop entersInserir {
        Send("{Enter}")
        Aguardar(delayCurto)
    }
    Aguardar(700) ; espera antes do Shift+Tab
    Send("+{Tab}")
    Aguardar(delayCurto)
    if (ativarComEnter) {
        Send("{Enter}")
        Aguardar(delayCurto)
    }
    if (tabFinal) {
        Send("{Tab}")
        Aguardar(delayCurto)
    }

    ; ---------- Insere cada valor, um de cada vez ----------
    valoresTexto := ""
    for valor in listaValores {
        SendText(valor)
        Aguardar(delayCurto)
        Send("{Tab}")
        Aguardar(delayCurto)
        Send("+{Tab}")
        Aguardar(delayCurto)

        valoresTexto .= (valoresTexto = "" ? "" : ",") . valor
    }

    ; ---------- Verifica (diagnóstico) se todos os valores parecem ter entrado ----------
    ; Cada valor inserido dispara um re-render AJAX (nova linha na tabela) —
    ; sem esperar assentar, a captura pode rodar antes do último valor
    ; terminar de aparecer no DOM.
    Aguardar(delayMedio)
    textoAtual := CapturarResumoPagina(200000)

    ; ÚNICO sinal tratado como falha de verdade: a própria página rejeitando
    ; o código (ex.: um código de classe "Normal" usado numa consulta de
    ; Inativos/Pensionistas), mostrando "Erro / Codigo informado nao
    ; localizado". Isso vem do servidor, não de uma leitura de texto
    ; ambígua — por isso é o único caso que aborta e avisa o usuário.
    ;
    ; Exige as duas palavras PRÓXIMAS uma da outra (mesma frase), não só
    ; presentes em qualquer lugar dos até 200000 chars da página inteira —
    ; bug corrigido na v1.1: do jeito que estava (dois InStr independentes,
    ; sem relação de proximidade), "informado" e "localizado" apareceriam
    ; como incompatibilidade mesmo vindo de dois pontos completamente sem
    ; relação da tela (ex.: uma coluna de endereço com "não localizado" em
    ; alguma linha da tabela de resultados + um rótulo qualquer com
    ; "informado" em outro canto da página) — um falso positivo que descarta
    ; uma seleção de códigos que na verdade funcionou.
    if RegExMatch(textoAtual, "i)informado.{0,60}localizado") {
        RegistrarEvento("Inserir " . campoBusca . ": codigo incompativel", "ERRO", "pagina reportou 'Codigo informado nao localizado' - um ou mais valores (" . valoresTexto . ") nao sao validos nesse contexto")
        return false
    }

    ; Restringe a leitura ao trecho DESSE campo (mesma lógica do "ainda ha
    ; valores" acima) — sem isso, um código curto (ex.: "2", "10") pode
    ; coincidir com texto de OUTRO campo/linha da tabela em qualquer lugar
    ; da página. Mesmo assim, essa comparação já se mostrou capaz de
    ; acusar "faltando" com a caixa certinha na tela — por isso vira só
    ; log (AVISO), não motivo pra travar o fluxo ou avisar o usuário.
    trechoAtual := TrechoDoCampo(textoAtual, campoBusca)
    faltando := ""
    for valor in listaValores
        if !InStr(trechoAtual, valor)
            faltando .= (faltando = "" ? "" : ",") . valor

    if (faltando = "")
        RegistrarEvento("Inserir " . campoBusca, "OK", "qtd=" . listaValores.Length . " valores=" . valoresTexto)
    else
        RegistrarEvento("Inserir " . campoBusca . ": valor(es) aparentemente faltando (checagem sujeita a falso alarme)", "AVISO", "faltando=" . faltando . " valores_inseridos=" . valoresTexto)

    return true
}
