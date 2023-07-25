# frozen_string_literal: true

class Prog::PageNexus < Prog::Base
  subject_is :page
  semaphore :resolve

  def self.assemble(summary)
    DB.transaction do
      p = Page.create_with_id(summary: summary)

      Strand.create(prog: "PageNexus", label: "start") { _1.id = p.id }
    end
  end

  label def start
    page.trigger
    hop_wait
  end

  label def wait
    when_resolve_set? do
      page.resolve
      pop "page is resolved"
    end

    nap 30
  end
end
