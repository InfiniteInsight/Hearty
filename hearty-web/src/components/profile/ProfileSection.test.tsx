import { expect, test } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useState } from "react";
import ProfileSection from "./ProfileSection";

interface Row { name: string }

function Harness({ initial = [] as Row[] }) {
  const [rows, setRows] = useState<Row[]>(initial);
  return (
    <ProfileSection<Row>
      title="Things"
      entries={rows}
      onChange={setRows}
      newEntry={() => ({ name: "" })}
      suggestions={["Peanuts"]}
      suggestionToEntry={(name) => ({ name })}
      renderFields={(e, update) => (
        <input aria-label="name" value={e.name} onChange={(ev) => update({ name: ev.target.value })} />
      )}
    />
  );
}

test("adds, edits, removes, and quick-adds a suggestion", async () => {
  render(<Harness />);
  await userEvent.click(screen.getByRole("button", { name: /add things/i }));
  const input = screen.getByLabelText("name");
  await userEvent.type(input, "oats");
  expect(screen.getByLabelText("name")).toHaveValue("oats");
  await userEvent.click(screen.getByRole("button", { name: /^Peanuts$/ }));
  expect(screen.getAllByLabelText("name")).toHaveLength(2);
  await userEvent.click(screen.getAllByRole("button", { name: /remove/i })[0]);
  expect(screen.getAllByLabelText("name")).toHaveLength(1);
});
