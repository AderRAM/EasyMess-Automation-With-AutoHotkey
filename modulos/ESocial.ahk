; =====================================================================
; ESocial.ahk
; Exportação e-Social (Consultas Dinâmicas → Consulta Eventos) — fluxo
; irmão do FAPS: MESMO site/mesmas funções de Página1/Página2 (Ctrl+F +
; Tab — LocalizarEFocar, InserirCampoMultiSelect, PreencherEExecutarPagina1,
; ValidarEExportarPagina2, VoltarParaPrimeiraPagina) são reaproveitadas
; diretamente daqui, sem duplicar nada, só a orquestração do ciclo muda.
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
        case "Inativos":
            return "INATIVOS"
        case "Pensionistas":
            return "PENSIONISTAS"
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

        ; ---------- VERIFICAÇÃO 0: precisa estar na página 1 ANTES de
        ; mexer (mesma recuperação de ProcessarCiclo, ver comentário lá) ----------
        if !AguardarPagina("PAGINA1", 5, &pagAtual) {
            RegistrarEvento("Verificacao inicial PAGINA1 (e-Social)", "AVISO", "preso em '" . pagAtual . "' — tentando recuperar (Voltar extra)")
            VoltarParaPrimeiraPagina(dataTag, logFile)
            AguardarPagina("PAGINA1", 5, &pagAtual)

            if (pagAtual != "PAGINA1") {
                FileAppend(dataTag . ";ABORTADO - esperava PAGINA1 no inicio do ciclo, detectado '" . pagAtual . "' | Etapa: verificacao inicial (e-Social)`n", logFile)
                RegistrarEvento("Verificacao inicial PAGINA1 (e-Social)", "ABORTADO", "detectado='" . pagAtual . "'")
                TrayTip("Ciclo abortado", dataTag . ": página inesperada no início do ciclo (" . pagAtual . ")", 16)
                return
            }
        }

        ; ---------- Reaplica Conta (código mensal de férias muda por mês)
        ; — direto via InserirCampoMultiSelect, com os MESMOS parâmetros
        ; que InserirContas usa pra "Conta" (ver Pagina1.ahk), só sem os
        ; efeitos colaterais de prefix/classe_atual.txt do FAPS. ----------
        listaContas := ObterContaESocial(chaveEntidade, mes)
        faltandoConta := ""
        if !InserirCampoMultiSelect(listaContas, "Conta", 1, true, true, "Matrícula:", 0, 2, &faltandoConta, "+{Enter}") {
            FileAppend(dataTag . ";ABORTADO - pagina rejeitou um ou mais codigos de Conta (entidade=" . chaveEntidade . ") | Etapa: Conta (e-Social)`n", logFile)
            RegistrarEvento("Aplicar Conta (e-Social)", "ABORTADO", "pagina rejeitou codigo(s), entidade=" . chaveEntidade)
            TrayTip("Ciclo abortado", dataTag . ": Conta rejeitada pela página (e-Social)", 16)
            VoltarParaPrimeiraPagina(dataTag, logFile)
            return
        }

        ; Verificacao imediata apos inserir a Conta: se faltou codigo, tenta
        ; uma vez apenas os faltantes (sem limpar o que ja entrou) e re-verifica.
        if (faltandoConta != "") {
            RegistrarEvento("Aplicar Conta (e-Social)", "AVISO", "faltando apos 1a insercao=" . faltandoConta . " - tentando reinserir apenas os faltantes")
            faltandoRetry := ""
            codigosFaltantes := DividirCodigos(faltandoConta)
            if (codigosFaltantes.Length > 0) {
                if !InserirCampoMultiSelect(codigosFaltantes, "Conta", 1, true, true, "Matrícula:", 0, 2, &faltandoRetry, "+{Enter}", false) {
                    FileAppend(dataTag . ";ABORTADO - pagina rejeitou codigo(s) de Conta ao reinserir faltantes (entidade=" . chaveEntidade . ") | Etapa: Conta (e-Social)`n", logFile)
                    RegistrarEvento("Aplicar Conta (e-Social)", "ABORTADO", "pagina rejeitou codigo(s) faltantes, entidade=" . chaveEntidade)
                    TrayTip("Ciclo abortado", dataTag . ": Conta rejeitada pela página (e-Social)", 16)
                    VoltarParaPrimeiraPagina(dataTag, logFile)
                    return
                }
                faltandoConta := faltandoRetry
            }
        }

        if (faltandoConta != "") {
            FileAppend(dataTag . ";ABORTADO - codigo(s) de Conta nao inserido(s) apos retry: " . faltandoConta . " (entidade=" . chaveEntidade . ") | Etapa: Conta (e-Social)`n", logFile)
            RegistrarEvento("Aplicar Conta (e-Social)", "ABORTADO", "faltando apos retry=" . faltandoConta . ", entidade=" . chaveEntidade)
            TrayTip("Ciclo abortado", dataTag . ": Conta incompleta (" . faltandoConta . ") (e-Social)", 16)
            VoltarParaPrimeiraPagina(dataTag, logFile)
            return
        }

        TrayTip("Conta (e-Social)", dataTag . ": códigos inseridos com sucesso (" . JuntarValores(listaContas) . ")", 1)

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
; Espelha Iniciar() (Export-Dados-2.2.ahk) — percorre o intervalo de meses
; de data1ES até data2ES. As 2 diferenças (pasta por ciclo, Conta
; reaplicada) já estão descritas no cabeçalho do arquivo.
IniciarESocial(data1ES, data2ES, chaveEntidade, pastaBaseES, logFileES) {
    global janelaAlvo, caminhoDownload, logAcoes, g_CicloEmExecucao

    ; Trava compartilhada com Iniciar() (FAPS) — ver comentário completo lá.
    ; e-Social mexe na MESMA janela do navegador, então também não pode
    ; rodar concorrente com um ciclo FAPS (ou outro e-Social) já em
    ; andamento.
    if (g_CicloEmExecucao) {
        MsgBox("Já tem um lote rodando (FAPS ou e-Social) — espere terminar (ou aperte Esc pra abortar) antes de iniciar outro. Rodar dois ao mesmo tempo corrompe a automação, já que os dois mexem na mesma aba do navegador.", "Aviso", 48)
        return
    }
    g_CicloEmExecucao := true

    Try {
        if (Trim(pastaBaseES) = "") {
            MsgBox("Defina a pasta base do e-Social na interface antes de iniciar.", "Aviso", 48)
            return
        }
        if (chaveEntidade = "") {
            MsgBox("Escolha a Entidade (Prefeitura/IPAM/Câmara/Inativos/Pensionistas) antes de iniciar.", "Aviso", 48)
            return
        }
        if !DetectarNavegador() {
            MsgBox("Não encontrei uma janela do Chrome nem do Firefox rodando o sistema.`nAbra o navegador com a página certa antes de iniciar.", "Aviso", 48)
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
    } Finally {
        g_CicloEmExecucao := false
    }
}
