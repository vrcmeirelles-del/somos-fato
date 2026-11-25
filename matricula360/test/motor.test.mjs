import test from 'node:test';
import assert from 'node:assert/strict';
import { stages, transitions, move, confirm, conversion, forecast, taxa, calcularProposta, normalizarEmail, normalizarTelefone, mascararEmail, mascararTelefone } from '../src/motor.mjs';

test('todas as etapas têm transições definidas', () => {
  for (const s of [...stages, 'perdido', 'cancelado']) assert.ok(Array.isArray(transitions[s]), s);
});

test('transição válida avança e inválida é recusada', () => {
  assert.equal(move({ stage: 'novo' }, 'contato').stage, 'contato');
  assert.throws(() => move({ stage: 'novo' }, 'matricula_comercial'), /Transição inválida/);
  assert.throws(() => move({ stage: 'novo' }, 'cancelado'), /Transição inválida/);
});

test('recuperação: perdido volta para contato', () => {
  assert.equal(move({ stage: 'perdido' }, 'contato').stage, 'contato');
});

test('confirmação incompleta é recusada e lista o que falta', () => {
  assert.throws(() => confirm({ stage: 'matricula_comercial', documental: true }), /falta validação financeira, academica/);
  assert.throws(() => confirm({ stage: 'pre_matricula', documental: true, financeira: true, academica: true }), /matrícula comercial/);
  assert.equal(confirm({ stage: 'matricula_comercial', documental: true, financeira: true, academica: true }).stage, 'confirmado');
});

test('zero é distinto de indisponível', () => {
  assert.equal(conversion([]), null);
  assert.equal(conversion([{ stage: 'novo' }]), 0);
  assert.equal(taxa(0, 0), null);
  assert.equal(taxa(0, 5), 0);
  assert.throws(() => taxa(-1, 2));
});

test('conversão usa o denominador informado', () => {
  assert.equal(conversion([{ stage: 'confirmado' }, { stage: 'novo' }, { stage: 'perdido' }, { stage: 'confirmado' }]), 0.5);
});

test('projeção matemática', () => {
  assert.equal(forecast(120, [0.7, 0.6, 0.3]), 953);
  assert.equal(forecast(0, [0.5]), 0);
  assert.throws(() => forecast(-1, [0.5]));
  assert.throws(() => forecast(10, [0]));
  assert.throws(() => forecast(10, [1.2]));
});

test('proposta: cálculo em centavos e limite de desconto', () => {
  const p = calcularProposta({ mensalidadeCentavos: 129000, descontoPct: 20, descontoMaxPct: 30 });
  assert.equal(p.valorFinalCentavos, 103200);
  assert.equal(p.exigeAprovacao, false);
  assert.equal(calcularProposta({ mensalidadeCentavos: 129000, descontoPct: 45, descontoMaxPct: 30 }).exigeAprovacao, true);
  assert.throws(() => calcularProposta({ mensalidadeCentavos: 129000, descontoPct: 120, descontoMaxPct: 30 }));
  assert.throws(() => calcularProposta({ mensalidadeCentavos: 129000, descontoPct: -1, descontoMaxPct: 30 }));
  assert.throws(() => calcularProposta({ mensalidadeCentavos: 129000, descontoPct: 10.123, descontoMaxPct: 30 }));
});

test('normalização e máscara de contato', () => {
  assert.equal(normalizarEmail(' Ana@Exemplo.Invalid '), 'ana@exemplo.invalid');
  assert.throws(() => normalizarEmail('sem-arroba'));
  assert.equal(normalizarTelefone('(00) 90000-1234'), '00900001234');
  assert.throws(() => normalizarTelefone('123'));
  assert.equal(mascararEmail('ana@exemplo.invalid'), 'a***@exemplo.invalid');
  assert.equal(mascararTelefone('00900001234'), '***1234');
});
