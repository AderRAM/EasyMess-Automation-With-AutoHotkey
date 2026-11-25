; =====================================================================
; EntrePaginas.ahk
; Orquestra um ciclo completo: garante que o navegador está na Página 1,
; chama o preenchimento/Executar (módulo Pagina1), depois a validação e
; exportação (módulo Pagina2), e por fim volta pra Página 1. É a "cola"
; entre os dois módulos de página — não faz nenhuma ação de UI própria
; além da verificação inicial de estado.

; ============================ UM CICLO COMPLETO ==========================
ProcessarCiclo(datainicio, datafim, dataTag, prefix, logFile) {
    global janelaAlvo, g_CicloAtual

    g_CicloAtual    := dataTag
    inicioCicloTick := A_TickCount
    RegistrarEvento("Inicio ciclo", "OK", "datainicio=" . datainicio . " datafim=" . datafim)

    Try {
        if !WinActive(janelaAlvo) {
            WinActivate(janelaAlvo)
            AguardarJanelaAtiva(janelaAlvo, 3)
        }

        if !AguardarPagina("PAGINA1", 5, &pagAtual) {
            RegistrarEvento("Verificacao inicial PAGINA1", "AVISO", "preso em '" . pagAtual . "' — tentando recuperar (Voltar extra)")
            VoltarParaPrimeiraPagina(dataTag, logFile)
            AguardarPagina("PAGINA1", 5, &pagAtual)

            if (pagAtual != "PAGINA1") {
                FileAppend(dataTag . ";ABORTADO - esperava PAGINA1 no inicio do ciclo, detectado '" . pagAtual . "' | Etapa: verificacao inicial (antes de localizar Referencia)`n", logFile)
                RegistrarEvento("Verificacao inicial PAGINA1", "ABORTADO", "detectado='" . pagAtual . "'")
                TrayTip("Ciclo abortado", dataTag . ": página inesperada no início do ciclo (" . pagAtual . ")", 16)
                return
            }
        }

        ; ---------- PÁGINA 1: preencher filtros e acionar Executar ----------
        if !PreencherEExecutarPagina1(datainicio, datafim, dataTag, logFile)
            return

        ; ---------- PÁGINA 2: validar, exportar e salvar ----------
        if !ValidarEExportarPagina2(dataTag, prefix, logFile)
            return

        VoltarParaPrimeiraPagina(dataTag, logFile)
    } Finally {
        RegistrarEvento("Fim ciclo", "OK", "duracao_total_ms=" . (A_TickCount - inicioCicloTick))
    }
}
