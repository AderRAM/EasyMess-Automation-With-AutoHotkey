; =====================================================================
; ESocial.ahk
; Exportação e-Social (Consultas Dinâmicas → Consulta Eventos) — fluxo
; irmão do FAPS: MESMO app/mesmas funções de Página1/Página2 (Ctrl+F +
; Tab — LocalizarEFocar, InserirCampoMultiSelect, PreencherEExecutarPagina1,
; ValidarEExportarPagina2, VoltarParaPrimeiraPagina) são reaproveitadas
; diretamente daqui, sem duplicar nada — só a orquestração do ciclo muda,
; por 3 motivos:
;
;   1) Entidade é FIXA (Prefeitura/IPAM/Câmara/Inativos e Pensionistas),
;      cada uma com sua própria lista de códigos de Conta — ver
;      ESOCIAL_CONTA_*/ObterContaESocial em Export-Dados-2.0.ahk (fonte:
;      tabela do "Manual - Exportação e-social - folha de pagamento.doc").
;
;   2) A Conta é REAPLICADA A CADA CICLO (mês), não só uma vez no começo
;      do lote como o FAPS faz hoje — porque um dos códigos ("IPAM Saúde -
;      Férias") muda por mês (8400+mês, ver CodigoFeriasIPAMSaude). Por
;      isso NÃO usa InserirContas (Pagina1.ahk) — aquela função também
;      grava prefix/classe_atual.txt do FAPS, efeito colateral que não
;      faz sentido aqui. Chama InserirCampoMultiSelect direto (a função de
;      baixo nível que InserirContas usa por baixo), com os mesmos
;      parâmetros que InserirContas já usa pra "Conta".
;
;   3) Pasta de destino tem uma SUBPASTA AUTOMÁTICA por ciclo
;      ("MMAAAA\CONSULTA EVENTOS", dentro da pasta base escolhida na
;      interface — confirmado pelo usuário com o exemplo
;      "A:\...\Exportados\072026\CONSULTA EVENTOS" pra julho/2026), em vez
;      de uma pasta única fixa pro lote inteiro. Isso é feito sobrescrevendo
;      a global "caminhoDownload" (a mesma que ValidarEExportarPagina2 já
;      lê) a cada ciclo — seguro porque o FAPS sempre resincroniza esse
;      valor a partir do próprio campo "Pasta de destino" antes de usar
;      (ver ExecutarProcessamento, em Interface.ahk), então não há
;      contaminação entre os dois fluxos mesmo compartilhando a variável.
;
; O nome do arquivo (dataTag + "_" + entidade + "_") NÃO entra nenhum
; código de conta, diferente do FAPS/RPC. E, ao contrário do FAPS/RPC (que
; só INSEREM esse prefixo antes do nome padrão que a página sugere na
; janela "Salvar como"), o e-Social SUBSTITUI o nome inteiro — o padrão
; sugerido termina num código gerado pelo sistema que precisa ser removido
; (pedido explícito do usuário), então no lugar dele o script escreve
; "Consulta Eventos" (ver ehESocial em ValidarEExportarPagina2, Pagina2.ahk).
; =====================================================================

; Mapeia o texto do dropdown "Entidade" (aba e-Social) pra chave interna
; usada por ObterContaESocial e pelo nome de arquivo. "" se não reconhecer.
ChaveEntidadeESocial(textoEntidade) {
    switch textoEntidade {
        case "Prefeitura":
            return "PREFEITURA"
        case "IPAM":
            return "IPAM"
        case "Câmara":
            return "CAMARA"
        case "Inativos e Pensionistas":
            return "INATIVOS_PENSIONISTAS"
    }
    return ""
}

; Monta o caminho completo da pasta de destino pra um ciclo (mês/ano)
; específico — pastaBase + "\MMAAAA\CONSULTA EVENTOS".
PastaCicloESocial(pastaBase, ano, mes) {
    return RTrim(pastaBase, "\/") . "\" . Format("{:02}{:04}", mes, ano) . "\CONSULTA EVENTOS"
}

; ============================ UM CICLO COMPLETO (e-Social) ==============
; Espelha ProcessarCiclo (EntrePaginas.ahk), com um passo a mais logo no
; início: reaplica a Conta (ver motivo 2 no cabeçalho do arquivo) antes de
; preencher Referência/Executar.
ProcessarCicloESocial(datainicio, datafim, dataTag, prefix, mes, chaveEntidade, logFile) {
    global janelaAlvo, g_CicloAtual

    g_CicloAtual    := dataTag
    inicioCicloTick := A_TickCount
    RegistrarEvento("Inicio ciclo e-Social", "OK", "datainicio=" . datainicio . " datafim=" . datafim . " entidade=" . chaveEntidade)

    Try {
        if !WinActive(janelaAlvo) {
            WinActivate(janelaAlvo)
            AguardarJanelaAtiva(janelaAlvo, 3)
        }

        ; ---------- VERIFICAÇÃO 0: temos que estar na página 1 ANTES de
        ; mexer (mesma recuperação de ProcessarCiclo, ver comentário lá) ----------
        if !AguardarPagina("PAGINA1", 5, &pagAtual) {
            RegistrarEvento("Verificacao inicial PAGINA1 (e-Social)", "AVISO", "preso em '" . pagAtual . "' — tentando recuperar (Voltar extra)")
            VoltarParaPrimeiraPagina(dataTag, logFile)
            AguardarPagina("PAGINA1", 5, &pagAtual)

            if (pagAtual != "PAGINA1") {
                FileAppend(dataTag . ";ABORTADO - esperava PAGINA1 no inicio do ciclo, detectado '" . pagAtual . "' | Etapa: verificacao inicial (e-Social)`n", logFile)
                RegistrarEvento("Verificacao inicial PAGINA1 (e-Social)", "ABORTADO", "detectado='" . pagAtual . "'")
                SoundBeep(500, 300)
                TrayTip("Ciclo abortado", dataTag . ": página inesperada no início do ciclo (" . pagAtual . ")", 16)
                return
            }
        }

        ; ---------- Reaplica Conta (código mensal de férias muda por mês)
        ; — direto via InserirCampoMultiSelect, com os MESMOS parâmetros
        ; que InserirContas usa pra "Conta" (ver Pagina1.ahk), só sem os
        ; efeitos colaterais de prefix/classe_atual.txt do FAPS. ----------
        listaContas := ObterContaESocial(chaveEntidade, mes)
        if !InserirCampoMultiSelect(listaContas, "Conta", 0, true, true, "Matrícula:", 0, 2) {
            FileAppend(dataTag . ";ABORTADO - pagina rejeitou um ou mais codigos de Conta (entidade=" . chaveEntidade . ") | Etapa: Conta (e-Social)`n", logFile)
            RegistrarEvento("Aplicar Conta (e-Social)", "ABORTADO", "pagina rejeitou codigo(s), entidade=" . chaveEntidade)
            SoundBeep(500, 300)
            TrayTip("Ciclo abortado", dataTag . ": Conta rejeitada pela página (e-Social)", 16)
            VoltarParaPrimeiraPagina(dataTag, logFile)
            return
        }

        ; ---------- PÁGINA 1: preencher Referência e acionar Executar
        ; (reaproveitado de Pagina1.ahk — mesmo app, mesmo mecanismo) ----------
        if !PreencherEExecutarPagina1(datainicio, datafim, dataTag, logFile)
            return

        ; ---------- PÁGINA 2: validar, exportar e salvar (reaproveitado
        ; de Pagina2.ahk) ---------- ehESocial=true: substitui o nome
        ; inteiro do arquivo em vez de só prefixar (ver ValidarEExportarPagina2).
        if !ValidarEExportarPagina2(dataTag, prefix, logFile, true)
            return

        VoltarParaPrimeiraPagina(dataTag, logFile)
    } Finally {
        RegistrarEvento("Fim ciclo e-Social", "OK", "duracao_total_ms=" . (A_TickCount - inicioCicloTick))
    }
}

; ============================ LOOP (e-Social) ============================
; Espelha Iniciar() (Export-Dados-2.0.ahk) — percorre o intervalo de meses
; de data1ES até data2ES. As 2 diferenças (pasta por ciclo, Conta
; reaplicada) já estão descritas no cabeçalho do arquivo.
IniciarESocial(data1ES, data2ES, chaveEntidade, pastaBaseES, logFileES) {
    global janelaAlvo, caminhoDownload, logAcoes

    if (Trim(pastaBaseES) = "") {
        MsgBox("Defina a pasta base do e-Social na interface antes de iniciar.", "Aviso", 48)
        return
    }
    if (chaveEntidade = "") {
        MsgBox("Escolha a Entidade (Prefeitura/IPAM/Câmara/Inativos e Pensionistas) antes de iniciar.", "Aviso", 48)
        return
    }
    if !WinExist(janelaAlvo) {
        MsgBox("Não encontrei a janela alvo (" . janelaAlvo . ").`nAjuste a variável janelaAlvo no topo do script.", "Aviso", 48)
        return
    }

    WinActivate(janelaAlvo)
    AguardarJanelaAtiva(janelaAlvo, 3)

    if !FileExist(logFileES)
        FileAppend("Ciclo;Motivo`n", logFileES)

    ; logAcoes (log_acoes.csv) é compartilhado com o FAPS — RegistrarEvento
    ; (Utilitarios.ahk) só faz FileAppend cego, sem checar cabeçalho; normalmente
    ; quem garante o cabeçalho é Iniciar() (FAPS), mas se o e-Social for a
    ; PRIMEIRA coisa rodada (antes de qualquer ciclo FAPS), precisa garantir
    ; aqui também.
    if !FileExist(logAcoes)
        FileAppend("Timestamp;Ciclo;Etapa;DuracaoMs;LimiteMs;Lento;Status;Detalhes`n", logAcoes)

    ano    := Integer(SubStr(data1ES, 1, 4))
    mes    := Integer(SubStr(data1ES, 5, 2))
    anoFim := Integer(SubStr(data2ES, 1, 4))
    mesFim := Integer(SubStr(data2ES, 5, 2))

    Loop {
        if (ano < anoFim) || (ano = anoFim && mes < mesFim)
            break

        datainicio := Format("{:02}/{:02}/{:04}", 1, mes, ano)
        datafim    := UltimoDiaDoMes(ano, mes)
        dataTag    := Format("{:04}{:02}", ano, mes)
        prefix     := chaveEntidade . "_"

        caminhoDownload := PastaCicloESocial(pastaBaseES, ano, mes)
        if !DirExist(caminhoDownload)
            DirCreate(caminhoDownload)

        ProcessarCicloESocial(datainicio, datafim, dataTag, prefix, mes, chaveEntidade, logFileES)

        mes--
        if (mes < 1) {
            mes := 12
            ano--
        }
    }

    MsgBox("Processo e-Social finalizado.`nVerifique " . logFileES . " para ciclos com erro.", "Concluído", 64)
}
