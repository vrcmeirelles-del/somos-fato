import { useCallback, useEffect, useRef, useState } from 'react';
import { ErroApi } from './supabase';

// Carrega dados de uma RPC; descarta respostas atrasadas (troca rápida de filtro) e expõe recarga.
export function useCarregar<T>(fn: () => Promise<T>, deps: unknown[]) {
  const [dados, setDados] = useState<T | null>(null);
  const [erro, setErro] = useState<ErroApi | Error | null>(null);
  const [carregando, setCarregando] = useState(true);
  const seq = useRef(0);
  const carregar = useCallback(async () => {
    const minha = ++seq.current;
    setCarregando(true);
    try {
      const d = await fn();
      if (minha === seq.current) { setDados(d); setErro(null); }
    } catch (e) {
      if (minha === seq.current) setErro(e as Error);
    } finally {
      if (minha === seq.current) setCarregando(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);
  useEffect(() => { void carregar(); }, [carregar]);
  return { dados, erro, carregando, recarregar: carregar };
}

// Executa uma ação com estado de envio e mensagem, evitando duplo clique.
export function useAcao() {
  const [enviando, setEnviando] = useState(false);
  const [mensagem, setMensagem] = useState<{ tipo: 'ok' | 'erro'; texto: string } | null>(null);
  const executar = useCallback(async (fn: () => Promise<string | void>) => {
    if (enviando) return;
    setEnviando(true); setMensagem(null);
    try {
      const texto = await fn();
      if (texto) setMensagem({ tipo: 'ok', texto });
    } catch (e) {
      setMensagem({ tipo: 'erro', texto: (e as Error).message });
    } finally {
      setEnviando(false);
    }
  }, [enviando]);
  return { enviando, mensagem, setMensagem, executar };
}
