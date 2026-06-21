import { expect, test } from "vitest";
import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { renderWithProviders } from "../test/utils";
import { useJournalFilters } from "./useJournalFilters";

function Probe() {
  const { filters, setFilters } = useJournalFilters();
  return (
    <div>
      <span data-testid="kw">{filters.keyword ?? "none"}</span>
      <span data-testid="page">{filters.page}</span>
      <button onClick={() => setFilters({ keyword: "rice" })}>set</button>
      <button onClick={() => setFilters({ page: 2 })}>page2</button>
      <button onClick={() => setFilters({ keyword: undefined })}>clear</button>
    </div>
  );
}

test("hydrates filters from URL query params", () => {
  renderWithProviders(<Probe />, { route: "/journal?keyword=oats&page=1" });
  expect(screen.getByTestId("kw").textContent).toBe("oats");
  expect(screen.getByTestId("page").textContent).toBe("1");
});

test("setting a filter resets page to 0", async () => {
  renderWithProviders(<Probe />, { route: "/journal?page=3" });
  await userEvent.click(screen.getByText("set"));
  expect(screen.getByTestId("kw").textContent).toBe("rice");
  expect(screen.getByTestId("page").textContent).toBe("0");
});

test("explicit page set is honored", async () => {
  renderWithProviders(<Probe />, { route: "/journal?keyword=oats" });
  await userEvent.click(screen.getByText("page2"));
  expect(screen.getByTestId("page").textContent).toBe("2");
  expect(screen.getByTestId("kw").textContent).toBe("oats");
});

test("clearing a filter removes it", async () => {
  renderWithProviders(<Probe />, { route: "/journal?keyword=oats" });
  await userEvent.click(screen.getByText("clear"));
  expect(screen.getByTestId("kw").textContent).toBe("none");
});
