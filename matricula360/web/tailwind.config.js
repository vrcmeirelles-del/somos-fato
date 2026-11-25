/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      fontFamily: { sans: ['"Inter Variable"', 'Inter', 'system-ui', 'Segoe UI', 'Roboto', 'sans-serif'] },
      colors: {
        // Identidade Matrícula 360°: azul-marinho institucional, azul tecnológico, branco e cinza-claro.
        marinho: { DEFAULT: '#0b2545', 800: '#0f2f57', 700: '#13315c', 600: '#1b3f73' },
        tec: { DEFAULT: '#1d6fe0', 600: '#1a5fc2', 400: '#4b8ff0', 100: '#e6f0fd', 50: '#f2f7fe' },
        ciano: '#14b8c4',
        fundo: '#f3f6fa', linha: '#e3e9f1', texto: '#0f1c2e', suave: '#5b6b80',
        ok: '#15803d', alerta: '#b45309', erro: '#b42318', faixa: '#fff7e0',
      },
      boxShadow: { cartao: '0 1px 2px rgba(11,37,69,.06), 0 1px 3px rgba(11,37,69,.08)' },
    },
  },
  plugins: [],
};
