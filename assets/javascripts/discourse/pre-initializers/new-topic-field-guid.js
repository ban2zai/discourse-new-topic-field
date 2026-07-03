import { captureTaskGuid } from "../lib/task-guid-cache";

export default {
  name: "new-topic-field-guid",
  before: "inject-discourse-objects",

  initialize() {
    captureTaskGuid();
  },
};
