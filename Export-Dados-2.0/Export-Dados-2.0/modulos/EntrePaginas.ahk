; =====================================================================
; EntrePaginas.ahk
; Orquestra um ciclo completo: garante que o navegador está na Página 1,
; chama o preenchimento/Executar (módulo Pagina1), depois a validação e
; exportação (módulo Pagina2), e por fim volta pra Página 1. É a "cola"
; entre os dois módulos de página — não faz nenhuma ação de UI própria
; além da verificação inicial de estado. Portado do V2 (era a função
; ProcessarCiclo inteira) sem mudança de comportamento, só dividido nas
; partes de página1/página2 (agora em módulos próprios).
; =====================================================================

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

        ; ---------- VERIFICAÇÃO 0: temos que estar na página 1 ANTES de mexer ----------
        ; Se o ciclo ANTERIOR travou em qualquer estado que não seja PAGINA1
        ; (PAGINA2, DESCONHECIDA, SEM_LEITURA — ex.: um menu/dropdown que
        ; ficou aberto), sem essa recuperação TODO ciclo seguinte abortaria
        ; em cascata na hora, sem nunca tentar de novo — desperdiçando o
        ; lote inteiro. Tenta um "Voltar" extra antes de desistir de vez.
        ; OBS: NAO usar {Escape} aqui — Esc é hotkey do próprio script
        ; (ExitApp) e Send("{Escape}") dispara esse hook, fechando o script
        ; no meio do ciclo em vez de recuperar.
        if !AguardarPagina("PAGINA1", 5, &pagAtual) {
            RegistrarEvento("Verificacao inicial PAGINA1", "AVISO", "preso em '" . pagAtual . "' — tentando recuperar (Voltar extra)")
            VoltarParaPrimeiraPagina(dataTag, logFile)
            AguardarPagina("PAGINA1", 5, &pagAtual)

            if (pagAtual != "PAGINA1") {
                FileAppend(dataTag . ";ABORTADO - esperava PAGINA1 no inicio do ciclo, detectado '" . pagAtual . "' | Etapa: verificacao inicial (antes de localizar Referencia)`n", logFile)
                RegistrarEvento("Verificacao inicial PAGINA1", "ABORTADO", "detectado='" . pagAtual . "'")
                SoundBeep(500, 300)
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
