export function Backlog({ titulo, itens }: { titulo: string; itens: string[] }) {
  return (
    <>
      <h1 className="mb-3 text-2xl font-bold sm:text-3xl">{titulo}</h1>
      <p className="mb-3 rounded-lg bg-faixa px-3.5 py-2.5">Fora do escopo do piloto. Planejado para depois do MVP, conforme a Bíblia-Mestra.</p>
      <ul className="list-disc pl-6">{itens.map((i) => <li key={i}>{i}</li>)}</ul>
    </>
  );
}
