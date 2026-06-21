import { afterEach, expect, test, vi } from "vitest";
import { saveBlob } from "./download";

afterEach(() => vi.restoreAllMocks());

test("saveBlob creates an object URL, clicks an anchor, and revokes", () => {
  const create = vi.fn(() => "blob:fake");
  const revoke = vi.fn();
  // jsdom doesn't implement these — stub them.
  vi.stubGlobal("URL", { ...URL, createObjectURL: create, revokeObjectURL: revoke });
  const click = vi.spyOn(HTMLAnchorElement.prototype, "click").mockImplementation(() => {});
  saveBlob(new Blob(["x"]), "f.csv");
  expect(create).toHaveBeenCalled();
  expect(click).toHaveBeenCalled();
  expect(revoke).toHaveBeenCalledWith("blob:fake");
});
