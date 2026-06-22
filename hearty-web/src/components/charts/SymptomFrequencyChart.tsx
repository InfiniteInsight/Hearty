import { Bar, BarChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import type { ChartDatum } from "../../lib/charts";

export default function SymptomFrequencyChart({ data }: { data: ChartDatum[] }) {
  if (data.length === 0) return <p className="text-text-faint text-sm">No symptoms in this period.</p>;
  return (
    <div className="h-56 w-full">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={data}>
          <XAxis dataKey="type" tick={{ fill: "var(--text-faint)", fontSize: 11 }} interval={0} angle={-30} textAnchor="end" height={60} />
          <YAxis allowDecimals={false} tick={{ fill: "var(--text-faint)", fontSize: 11 }} />
          <Tooltip contentStyle={{ background: "#112240", border: "1px solid var(--surface-border)", borderRadius: 8 }} />
          <Bar dataKey="count" fill="var(--accent-red)" radius={[4, 4, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
