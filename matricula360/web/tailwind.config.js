/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        marinho: '#102f4c', acao: '#155d90', fundo: '#f4f7fb', linha: '#dce5ef', texto: '#152b43', suave: '#52677b',
        ok: '#1f7a45', alerta: '#a35a00', erro: '#b3261e', faixa: '#fff7e0',
      },
    },
  },
  plugins: [],
};
